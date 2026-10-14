const http = require('http');

function makeRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ statusCode: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', (err) => reject(err));
    if (postData) {
      req.write(JSON.stringify(postData));
    }
    req.end();
  });
}

async function runTrashSystemTests() {
  console.log('🧪 ========================================================');
  console.log('🧪 RUNNING PRODUCTION TRASH / RECYCLE BIN VALIDATION SUITE');
  console.log('🧪 ========================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
      failed++;
    }
  }

  // 1. Setup Tenant 1 (Facility Admin)
  const tenant1Email = `trash_admin_${Date.now()}@hospital1.eg`;
  const reg1 = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Al-Amal Specialized Hospital',
    workEmail: tenant1Email,
    password: 'Password123!',
    subscriptionPlanId: 'plan_standard'
  });
  const t1Token = reg1.body?.token;
  const t1FacilityId = reg1.body?.facility?.id;
  assert(reg1.statusCode === 201 && !!t1Token, 'Tenant 1 registered and JWT issued');

  // 2. Setup Tenant 2 for Isolation Testing
  const tenant2Email = `trash_admin2_${Date.now()}@hospital2.eg`;
  const reg2 = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Nile Delta Medical Center',
    workEmail: tenant2Email,
    password: 'Password123!',
    subscriptionPlanId: 'plan_standard'
  });
  const t2Token = reg2.body?.token;
  assert(reg2.statusCode === 201 && !!t2Token, 'Tenant 2 registered for isolation testing');

  // 3. Create items in Tenant 1: Gap, Action Plan, License, Document
  const createGap = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/gaps', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${t1Token}` }
  }, { title: 'Emergency Department Triage Non-Compliance', standardCode: 'ED.01', priority: 'HIGH' });
  const gapId = createGap.body?.gap?.id || createGap.body?.id;
  assert(createGap.statusCode === 200 || createGap.statusCode === 201, `Gap created: ${gapId}`);

  const createPlan = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/action-plans', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${t1Token}` }
  }, { title: 'Upgrade Fire Suppression System in ICU', targetDate: '2026-12-31', status: 'IN_PROGRESS' });
  const planId = createPlan.body?.actionPlan?.id;
  assert(createPlan.statusCode === 201 && !!planId, `Action Plan created: ${planId}`);

  const createLic = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/licenses', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${t1Token}` }
  }, { licenseName: 'Radiation Safety Operating License', issuer: 'Egyptian Atomic Authority', expiryDate: '2027-01-15' });
  const licId = createLic.body?.license?.id;
  assert(createLic.statusCode === 201 && !!licId, `License created: ${licId}`);

  const createDoc = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/documents/upload', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${t1Token}` }
  }, {
    title: 'Infection Prevention & Control Policy 2026',
    category: 'IPC',
    base64Content: Buffer.from('%PDF-1.4 test dummy pdf content').toString('base64'),
    originalName: 'ipc_policy_2026.pdf',
    mimeType: 'application/pdf'
  });
  const docId = createDoc.body?.document?.id;
  assert(createDoc.statusCode === 201 && !!docId, `Document created: ${docId}`);

  // 4. Verify initial trash is empty
  const initialTrash = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(initialTrash.statusCode === 200 && initialTrash.body.trash.length === 0, 'Trash is initially empty');

  // 5. Soft-delete the Gap
  const delGap = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/gaps/${gapId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(delGap.statusCode === 200 && delGap.body.success === true, 'Gap soft-deleted successfully');

  // 6. Verify Gap is excluded from active GET /api/gaps
  const activeGaps = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/gaps', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  const foundInActiveGaps = activeGaps.body?.gaps?.some(g => g.id === gapId);
  assert(!foundInActiveGaps, 'Gap is no longer returned in active gaps list');

  // 7. Verify Gap appears in GET /api/trash
  const trashAfterGap = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  const trashedGap = trashAfterGap.body?.trash?.find(t => t.item_id === gapId);
  assert(!!trashedGap, 'Gap appears in Trash list');
  assert(trashedGap?.item_type === 'gap', 'Trash entry has correct item_type');
  assert(trashedGap?.deleted_by === tenant1Email, 'Trash entry preserves deleted_by user');
  assert(!!trashedGap?.deleted_at, 'Trash entry preserves deleted_at timestamp');

  // 8. Soft-delete Action Plan, License, and Document
  const delPlan = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/action-plans/${planId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(delPlan.statusCode === 200 && delPlan.body.success === true, 'Action Plan soft-deleted');

  const delLic = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/licenses/${licId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(delLic.statusCode === 200 && delLic.body.success === true, 'License soft-deleted');

  const delDoc = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/documents/${docId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(delDoc.statusCode === 200 && delDoc.body.success === true, 'Document soft-deleted');

  // 9. Check Trash contains all 4 items
  const fullTrash = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(fullTrash.body?.trash?.length === 4, `Trash contains 4 items (got ${fullTrash.body?.trash?.length})`);

  // 10. Filter Trash by type
  const filterGaps = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash?type=gap', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(filterGaps.body?.trash?.length === 1 && filterGaps.body.trash[0].item_type === 'gap', 'Trash filter by type=gap works');

  // 11. Search Trash by keyword
  const searchTrash = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash?search=Radiation', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(searchTrash.body?.trash?.length === 1 && searchTrash.body.trash[0].item_name.includes('Radiation'), 'Trash search by keyword works');

  // 12. Tenant 2 Isolation Test: Cannot see Tenant 1 trash
  const t2Trash = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t2Token}` }
  });
  assert(t2Trash.body?.trash?.length === 0, 'Tenant 2 cannot see Tenant 1 trash (multi-tenant isolation verified)');

  // 13. Tenant 2 Isolation Test: Cannot restore Tenant 1 trash item
  const gapTrashEntryId = trashedGap.id;
  const t2CrossRestore = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/trash/${gapTrashEntryId}/restore`, method: 'POST',
    headers: { 'Authorization': `Bearer ${t2Token}` }
  });
  assert(t2CrossRestore.statusCode === 404, 'Cross-tenant restore blocked (HTTP 404 Not Found)');

  // 14. Restore single item: Gap
  const restoreGap = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/trash/${gapTrashEntryId}/restore`, method: 'POST',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(restoreGap.statusCode === 200 && restoreGap.body.success === true, 'Gap restored successfully');

  // Verify Gap is back in active list
  const activeGapsAfterRestore = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/gaps', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(activeGapsAfterRestore.body?.gaps?.some(g => g.id === gapId), 'Gap reappeared in active gaps list');

  // Verify Gap is gone from Trash
  const trashAfterRestore = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(trashAfterRestore.body?.trash?.length === 3, 'Trash count decreased to 3');

  // 15. Test Restore All
  const restoreAll = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash/restore-all', method: 'POST',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(restoreAll.statusCode === 200 && restoreAll.body.restoredCount === 3, 'Restore All succeeded with 3 items');

  const trashAfterRestoreAll = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(trashAfterRestoreAll.body?.trash?.length === 0, 'Trash is now completely empty after Restore All');

  // 16. Soft-delete again for Permanent Delete & Empty Trash tests
  await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/action-plans/${planId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/licenses/${licId}`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });

  const trashBeforePerm = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  const planTrashEntry = trashBeforePerm.body?.trash?.find(t => t.item_id === planId);
  assert(!!planTrashEntry, 'Action plan trashed again for permanent delete test');

  // 17. Permanent Delete of single item
  const permDel = await makeRequest({
    hostname: 'localhost', port: 3000, path: `/api/trash/${planTrashEntry.id}/permanent`, method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(permDel.statusCode === 200 && permDel.body.success === true, 'Single item permanently deleted');

  // 18. Empty Trash
  const emptyRes = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash/empty', method: 'DELETE',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(emptyRes.statusCode === 200 && emptyRes.body.success === true, 'Empty Trash executed successfully');

  const trashFinal = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/trash', method: 'GET',
    headers: { 'Authorization': `Bearer ${t1Token}` }
  });
  assert(trashFinal.body?.trash?.length === 0, 'Trash is confirmed empty after Empty Trash');

  console.log('\n📊 ========================================================');
  console.log(`📊 TRASH SUITE RESULTS: ${passed} PASSED, ${failed} FAILED`);
  console.log('📊 ========================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runTrashSystemTests().catch(err => {
  console.error('Test runner fatal error:', err);
  process.exit(1);
});
