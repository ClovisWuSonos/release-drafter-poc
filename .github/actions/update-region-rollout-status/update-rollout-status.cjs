const STATUS_EMOJI = { complete: '✅', failed: '❌', 'rolled-back': '⏪' };
const START = '<!-- rollout-status:start -->';
const END = '<!-- rollout-status:end -->';

async function updateRolloutStatus({ github, core, context, tag, regionsJson, rolledBackTo }) {
  let regions;
  try {
    regions = JSON.parse(regionsJson);
  } catch (e) {
    core.setFailed(`invalid regions JSON: ${e.message}`);
    return;
  }
  if (!Array.isArray(regions) || regions.length === 0) {
    core.setFailed('regions must be a non-empty JSON array');
    return;
  }
  if (rolledBackTo && rolledBackTo === tag) {
    core.setFailed('reverted-to-tag must differ from tag');
    return;
  }

  const seen = new Set();
  for (const entry of regions) {
    const { region, status } = entry ?? {};
    if (typeof region !== 'string' || typeof status !== 'string') {
      core.setFailed('each entry must have string "region" and "status" fields');
      return;
    }
    if (!Object.hasOwn(STATUS_EMOJI, status)) {
      core.setFailed(`invalid status: '${status}'`);
      return;
    }
    if (!/^[a-z]{2}(?:-gov)?-[a-z]+-\d+$/.test(region)) {
      core.setFailed(`invalid region: '${region}'`);
      return;
    }
    if (seen.has(region)) {
      core.setFailed(`duplicate region: '${region}'`);
      return;
    }
    seen.add(region);
  }

  if (rolledBackTo && !regions.every(({ status }) => status === 'rolled-back')) {
    core.setFailed("all statuses must be 'rolled-back' when reverted-to-tag is supplied");
    return;
  }
  if (!rolledBackTo && regions.some(({ status }) => status === 'rolled-back')) {
    core.setFailed("status 'rolled-back' requires reverted-to-tag");
    return;
  }

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
  if (rolledBackTo && releaseInfo.isDraft) {
    core.setFailed('rollback requires a published release');
    return;
  }

  const { data: release } = await github.rest.repos.getRelease({
    owner: context.repo.owner,
    repo: context.repo.repo,
    release_id: releaseInfo.databaseId,
  });

  const date = new Date().toISOString() + ' (UTC)';
  const pending = new Map(regions.map(({ region, status }) => [region,
    rolledBackTo
      ? `${region}: ${STATUS_EMOJI['rolled-back']} rolled-back on ${date}, production reverted to ${rolledBackTo}`
      : `${region}: ${STATUS_EMOJI[status]} ${status}`,
  ]));

  let body = (release.body ?? '').replace(/\r\n/g, '\n');

  if (body.includes(START) !== body.includes(END)) {
    core.setFailed(`rollout-status block is malformed: missing ${body.includes(START) ? END : START}`);
    return;
  }

  if (body.includes(START)) {
    const lines = body.split('\n');
    const result = [];
    let inBlock = false;
    for (const line of lines) {
      if (line.trim() === START) {
        inBlock = true;
        result.push(line);
      } else if (line.trim() === END) {
        for (const row of pending.values()) result.push(row);
        result.push(line);
        inBlock = false;
      } else if (inBlock) {
        const sep = line.indexOf(': ');
        const region = sep !== -1 ? line.slice(0, sep) : null;
        if (region && pending.has(region)) {
          result.push(pending.get(region));
          pending.delete(region);
        } else {
          result.push(line);
        }
      } else {
        result.push(line);
      }
    }
    body = result.join('\n');
  } else {
    body = `${body}\n\n${START}\n## Rollout Status\n\n${[...pending.values()].join('\n')}\n${END}\n`;
  }

  await github.rest.repos.updateRelease({
    owner: context.repo.owner,
    repo: context.repo.repo,
    release_id: release.id,
    body,
  });
}

module.exports = { updateRolloutStatus };
