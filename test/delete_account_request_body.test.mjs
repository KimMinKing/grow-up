import assert from 'node:assert/strict';
import test from 'node:test';
import { readSmallJson } from '../supabase/functions/delete-account/request_body.mjs';

function request(body) {
  return new Request('https://example.invalid/delete-account', {
    method: 'POST',
    body,
  });
}

test('accepts a small JSON confirmation', async () => {
  assert.deepEqual(await readSmallJson(request('{"confirmation":"DELETE_ACCOUNT"}')),
    { value: { confirmation: 'DELETE_ACCOUNT' } });
});

test('rejects oversized bodies without relying on Content-Length', async () => {
  const oversized = request('x'.repeat(1025));
  oversized.headers.delete('content-length');
  assert.deepEqual(await readSmallJson(oversized),
    { error: 'request_too_large' });
});

test('rejects malformed JSON and invalid UTF-8', async () => {
  assert.deepEqual(await readSmallJson(request('{bad')),
    { error: 'invalid_request' });
  assert.deepEqual(await readSmallJson(request(Uint8Array.of(0xff))),
    { error: 'invalid_request' });
});
