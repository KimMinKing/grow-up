import assert from 'node:assert/strict';
import test from 'node:test';
import { createDeletionApi } from '../web/delete-account.mjs';

const config = {
  supabaseUrl: 'https://example.supabase.co',
  publishableKey: 'sb_publishable_test',
};

test('OTP request cannot create a new account', async () => {
  const calls = [];
  const api = createDeletionApi(config, async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response('{}', { status: 200 });
  });
  await api.requestCode('member@example.com');
  assert.equal(calls[0].url, 'https://example.supabase.co/auth/v1/otp');
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    email: 'member@example.com', create_user: false,
  });
  assert.equal(calls[0].options.headers.apikey, config.publishableKey);
});

test('verified email and token are required before deletion', async () => {
  const calls = [];
  const api = createDeletionApi(config, async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).endsWith('/verify')) {
      return Response.json({
        access_token: 'verified-token',
        user: { email: 'Member@Example.com' },
      });
    }
    return Response.json({ deleted: true });
  });
  const session = await api.verifyCode('member@example.com', '123456');
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    email: 'member@example.com', token: '123456', type: 'email',
  });
  await api.deleteAccount(session);
  assert.equal(calls[1].url,
    'https://example.supabase.co/functions/v1/delete-account');
  assert.equal(calls[1].options.headers.Authorization,
    'Bearer verified-token');
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    confirmation: 'DELETE_ACCOUNT', email: 'Member@Example.com',
  });
});

test('wrong account or unconfirmed deletion is rejected', async () => {
  const wrongEmail = createDeletionApi(config, async () => Response.json({
    access_token: 'token', user: { email: 'other@example.com' },
  }));
  await assert.rejects(() => wrongEmail.verifyCode('member@example.com', '123456'),
    /invalid_session/);

  const notDeleted = createDeletionApi(config,
    async () => Response.json({ deleted: false }));
  await assert.rejects(() => notDeleted.deleteAccount({
    accessToken: 'token', email: 'member@example.com',
  }), /deletion_unconfirmed/);
});

test('private keys and insecure API origins are rejected', () => {
  assert.throws(() => createDeletionApi({
    supabaseUrl: 'http://example.supabase.co',
    publishableKey: 'sb_publishable_test',
  }), /invalid_public_config/);
  assert.throws(() => createDeletionApi({
    supabaseUrl: 'https://example.supabase.co',
    publishableKey: 'sb_secret_do-not-publish',
  }), /invalid_public_config/);
});
