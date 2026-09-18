const STATUS_EMOJI = {
  'success':     '✅',
  'failed':      '❌',
  'in-progress': '🔄',
  'rolled-back': '⏪',
};

const START = '<!-- rollout-status:start -->';
const END   = '<!-- rollout-status:end -->';

async function updateRolloutStatus({ github, core, context, tag, regions, rolledBackTo }) {
  // --- validate inputs ---
  let regionList;
  try {
    regionList = JSON.parse(regions);
  } catch (e) {
    core.setFailed(`regions is not valid JSON: ${e.message}`);
    return;
  }

  if (!Array.isArray(regionList) || regionList.length === 0) {
    core.setFailed('regions must be a non-empty JSON array');
    return;
  }

  for (const entry of regionList) {
    if (!entry.region || typeof entry.region !== 'string') {
      core.setFailed(`each entry must have a string 'region' field`);
      return;
    }
    if (!entry.status || typeof entry.status !== 'string') {
      core.setFailed(`each entry must have a string 'status' field`);
      return;
    }
    if (!Object.hasOwn(STATUS_EMOJI, entry.status)) {
      core.setFailed(
        `invalid status '${entry.status}' for region '${entry.region}'. ` +
        `Valid values: ${Object.keys(STATUS_EMOJI).join(', ')}`
      );
      return;
    }
    if (!/^[a-z]{2}(?:-gov)?-[a-z]+-\d+$/.test(entry.region)) {
      core.setFailed(`invalid region format: '${entry.region}'`);
      return;
    }
  }

  // --- find the release ---
  const gql = await github.graphql(`
    query($owner: String!, $repo: String!, $tag: String!) {
      repository(owner: $owner, name: $repo) {
        release(tagName: $tag) { databaseId isDraft }
      }
    }
  `, { owner: context.repo.owner, repo: context.repo.repo, tag });

  const releaseInfo = gql.repository.release;
  if (!releaseInfo) {
    core.setFailed(`no release found for tag '${tag}'`);
    return;
  }

  const { data: release } = await github.rest.repos.getRelease({
    owner: context.repo.owner,
    repo: context.repo.repo,
    release_id: releaseInfo.databaseId,
  });

  // --- build row text for each region ---
  const date = new Date().toISOString().split('T')[0];
  const rows = {};
  for (const { region, status } of regionList) {
    if (status === 'rolled-back') {
      let row = `${region}: ${STATUS_EMOJI['rolled-back']} rolled-back on ${date}`;
      if (rolledBackTo) row += `, production reverted to ${rolledBackTo}`;
      rows[region] = row;
    } else {
      rows[region] = `${region}: ${STATUS_EMOJI[status]} ${status}`;
    }
  }

  // --- upsert the rollout-status block ---
  let body = release.body ?? '';

  if (body.includes(START) && !body.includes(END)) {
    core.setFailed(`rollout-status block is malformed: found '${START}' but no matching '${END}'`);
    return;
  }

  if (body.includes(START)) {
    // Update existing block: overwrite matching region rows, append new ones.
    const lines = body.split('\n');
    const result = [];
    let inBlock = false;
    const written = new Set();

    for (const line of lines) {
      if (line === START) {
        inBlock = true;
        result.push(line);
        continue;
      }
      if (line === END) {
        // Append any regions that weren't already in the block
        for (const [region, row] of Object.entries(rows)) {
          if (!written.has(region)) result.push(row);
        }
        result.push(line);
        inBlock = false;
        continue;
      }
      if (inBlock) {
        const matched = Object.keys(rows).find(r => line.startsWith(`${r}: `));
        if (matched) {
          result.push(rows[matched]);
          written.add(matched);
        } else {
          result.push(line);
        }
      } else {
        result.push(line);
      }
    }
    body = result.join('\n');
  } else {
    // No block yet — append a fresh one.
    const rowLines = Object.values(rows).join('\n');
    body = `${body}\n\n${START}\n## Rollout Status\n\n${rowLines}\n${END}\n`;
  }

  await github.rest.repos.updateRelease({
    owner: context.repo.owner,
    repo: context.repo.repo,
    release_id: release.id,
    body,
  });

  const label = releaseInfo.isDraft ? 'draft' : 'published';
  core.info(`Updated rollout status for ${regionList.length} region(s) on ${label} release '${tag}'`);
}

module.exports = { updateRolloutStatus };
