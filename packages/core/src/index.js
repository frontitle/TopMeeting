// SPDX-License-Identifier: Apache-2.0
// Platform-neutral contracts. No filesystem, network, credential or UI imports.
export const protocolVersion = 1;
export function searchMeetings(meetings, query = '') {
  const terms = query.trim().toLocaleLowerCase().split(/\s+/u).filter(Boolean);
  return meetings.filter(m => !m.deletedAt && terms.every(term => [m.title, m.notes, m.context,
    ...(m.lines ?? []).flatMap(l => [l.text, l.speaker]), ...Object.values(m.voiceNames ?? {})]
    .some(value => typeof value === 'string' && value.toLocaleLowerCase().includes(term))));
}
function indexed(lines) {
  const result = new Map();
  for (const line of lines) {
    if (!line.id || result.has(line.id)) throw new Error('Duplicate or missing source ID');
    result.set(line.id, line);
  }
  return result;
}
export function transcriptDelta(previous, current) {
  const before = indexed(previous), after = indexed(current);
  return {
    added: current.filter(l => !before.has(l.id)),
    changed: current.filter(l => before.has(l.id) && JSON.stringify(before.get(l.id)) !== JSON.stringify(l)),
    deleted: previous.filter(l => !after.has(l.id)).map(l => l.id)
  };
}
export function applySummaryPatch(state, patch, sources) {
  if (patch.protocolVersion !== protocolVersion || !patch.id) throw new Error('Unsupported patch');
  if ((state.appliedPatchIDs ?? []).includes(patch.id)) return state;
  if (patch.baseRevision !== state.revision) throw new Error('Stale summary revision');
  const known = indexed(sources);
  const items = new Map(state.items.map(item => [item.id, structuredClone(item)]));
  if (!Array.isArray(patch.operations)) throw new Error('Missing operations');
  for (const op of patch.operations) {
    if (op.type === 'delete') {
      if (!items.has(op.id)) throw new Error('Unknown summary item');
      items.delete(op.id);
    } else if (op.type === 'upsert') {
      const item = op.item;
      if (!item?.id || typeof item.text !== 'string' || !Array.isArray(item.sources) || !item.sources.length)
        throw new Error('Summary item requires evidence');
      if (!['fact','proposal','decision','action','open-question'].includes(item.kind)) throw new Error('Unknown item kind');
      for (const ref of item.sources) {
        const source = known.get(ref.id);
        if (!source || source.revision !== ref.revision) throw new Error('Unknown or stale source');
      }
      items.set(item.id, structuredClone(item));
    } else throw new Error('Unknown operation');
  }
  return { revision:state.revision+1, items:[...items.values()], appliedPatchIDs:[...(state.appliedPatchIDs ?? []),patch.id] };
}
