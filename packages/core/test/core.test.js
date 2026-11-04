import { test } from 'node:test';
import assert from 'node:assert/strict';
import { searchMeetings, transcriptDelta, applySummaryPatch } from '../src/index.js';
test('search notes and speaker names without resurrecting deleted meetings', () => {
  const meeting = {id:'m',title:'Review',notes:'预算 confirmed',lines:[{text:'Discuss launch',speaker:'林悦'}]};
  assert.equal(searchMeetings([meeting,{...meeting,deletedAt:'today'}],'预算 林悦').length,1);
  assert.equal(searchMeetings([meeting],'REVIEW launch').length,1);
});
test('corrections and deletions produce deltas rather than entire transcript', () => {
  const before = [{id:'a',text:'旧词'},{id:'b',text:'remove'}];
  assert.deepEqual(transcriptDelta(before,[{id:'a',text:'纠正词'},{id:'c',text:'new'}]),{added:[{id:'c',text:'new'}],changed:[{id:'a',text:'纠正词'}],deleted:['b']});
  assert.throws(()=>transcriptDelta([],[{id:'a'},{id:'a'}]));
});
test('summary patches are atomic, evidenced, revision-checked and idempotent', () => {
  const state = {revision:0,items:[],appliedPatchIDs:[]};
  const source = [{id:'line',revision:2}];
  const item = {id:'item',kind:'proposal',text:'建议明天验收',sources:[{id:'line',revision:2}]};
  const patch = {protocolVersion:1,id:'patch',baseRevision:0,operations:[{type:'upsert',item}]};
  const next = applySummaryPatch(state,patch,source);
  assert.equal(next.items[0].kind,'proposal');
  assert.equal(applySummaryPatch(next,patch,source),next);
  assert.throws(()=>applySummaryPatch(next,{...patch,id:'different'},source),/Stale/);
  assert.throws(()=>applySummaryPatch(state,patch,[{id:'line',revision:3}]),/stale/);
  assert.throws(()=>applySummaryPatch(state,{...patch,operations:[...patch.operations,{type:'bogus'}]},source));
  assert.deepEqual(state.items,[]);
});
