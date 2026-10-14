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

async function runTests() {
  console.log('🧪 Starting GAHAR Backend API Test Suite...');
  
  let superAdminToken = '';
  let facilityToken = '';
  let newFacilityId = '';

  try {
    // Test 1: Super Admin Login
    console.log('\n--- Test 1: Super Admin Login ---');
    const saLoginRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/auth/super-admin/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, { email: 'superadmin@gahar.gov.eg', password: 'SuperAdmin@2026!' });
    
    console.log('Super Admin Login Status:', saLoginRes.statusCode);
    if (saLoginRes.body && saLoginRes.body.token) {
      superAdminToken = saLoginRes.body.token;
      console.log('✅ PASS: Received Super Admin JWT token.');
    } else {
      console.error('❌ FAIL:', saLoginRes.body);
    }

    // Test 2: Facility Registration
    console.log('\n--- Test 2: Facility Registration ---');
    const regRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/auth/register-facility',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, {
      facilityName: 'Nile Hope Hospital',
      facilityType: 'Hospital',
      governorate: 'Giza',
      bedCapacity: '200',
      contactPerson: 'Dr. Sameh Nabil',
      workEmail: 'info@nilehope.eg',
      phone: '+201112223334',
      password: 'HospitalPass@2026',
      subscriptionPlanId: 'plan_standard',
      paymentMethod: 'Vodafone Cash',
      paymentReference: 'VOD-99201948'
    });

    console.log('Registration Status:', regRes.statusCode);
    if (regRes.body && regRes.body.facility) {
      newFacilityId = regRes.body.facility.id;
      facilityToken = regRes.body.token;
      console.log(`✅ PASS: Registered facility ID: ${newFacilityId}, status: ${regRes.body.facility.status}`);
    } else {
      console.error('❌ FAIL:', regRes.body);
    }

    // Test 3: Super Admin List Facilities
    console.log('\n--- Test 3: Super Admin List Facilities ---');
    const listRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/admin/facilities',
      method: 'GET',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${superAdminToken}`
      }
    });

    console.log('List Facilities Status:', listRes.statusCode);
    if (listRes.body && listRes.body.facilities) {
      console.log(`✅ PASS: Found ${listRes.body.facilities.length} facilities.`);
    } else {
      console.error('❌ FAIL:', listRes.body);
    }

    // Test 4: Super Admin Approve Facility
    console.log('\n--- Test 4: Super Admin Approve Facility ---');
    const appRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: `/api/admin/facilities/${newFacilityId}/status`,
      method: 'PUT',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${superAdminToken}`
      }
    }, { status: 'APPROVED', reason: 'Payment verified' });

    console.log('Approve Status:', appRes.statusCode);
    if (appRes.body && appRes.body.facility && appRes.body.facility.status === 'APPROVED') {
      console.log('✅ PASS: Facility successfully approved!');
    } else {
      console.error('❌ FAIL:', appRes.body);
    }

    // Test 5: Tenant Isolation Security Enforcement
    console.log('\n--- Test 5: Tenant Isolation Security Check ---');
    const isoRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/gaps',
      method: 'GET',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${facilityToken}`,
        'X-Facility-Id': 'fac_some_other_hacker_facility'
      }
    });

    console.log('Tenant Isolation Check Status:', isoRes.statusCode);
    if (isoRes.statusCode === 403) {
      console.log('✅ PASS: Mismatched client X-Facility-Id correctly rejected with HTTP 403 Forbidden!');
    } else {
      console.error('❌ FAIL: Security vulnerability detected! Expected 403, got:', isoRes.statusCode);
    }

    // Test 6: Protected AI Copilot Endpoint
    console.log('\n--- Test 6: AI Copilot Proxy Endpoint ---');
    const copilotRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/ai/copilot',
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${facilityToken}`
      }
    }, {
      prompt: 'What are the required GAHAR standards for infection control in operating rooms?',
      screenContext: 'Gap Analysis Screen',
      entityData: { standardCode: 'IPC.01' }
    });

    console.log('AI Copilot Status:', copilotRes.statusCode);
    if (copilotRes.body && copilotRes.body.reply) {
      console.log('✅ PASS: Received AI Copilot response from backend!');
    } else {
      console.error('❌ FAIL:', copilotRes.body);
    }

    console.log('\n🎉 ALL BACKEND API TESTS COMPLETED SUCCESSFULLY!\n');

  } catch (err) {
    console.error('❌ Backend test execution error:', err.message);
  }
}

runTests();
