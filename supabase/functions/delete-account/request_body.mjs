export async function readSmallJson(request, maxBytes = 1024) {
  if (!request.body) return { error: 'invalid_request' };
  const reader = request.body.getReader();
  const chunks = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteCount += value.byteLength;
      if (byteCount > maxBytes) {
        await reader.cancel().catch(() => {});
        return { error: 'request_too_large' };
      }
      chunks.push(value);
    }
  } catch (_) {
    return { error: 'invalid_request' };
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return { value: JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) };
  } catch (_) {
    return { error: 'invalid_request' };
  }
}
