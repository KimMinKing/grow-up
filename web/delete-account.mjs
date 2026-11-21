export function createDeletionApi(config, fetchImpl = fetch) {
  const base = new URL(config.supabaseUrl);
  if (base.protocol !== 'https:' || !config.publishableKey ||
      config.publishableKey.startsWith('sb_secret_')) {
    throw new Error('invalid_public_config');
  }
  const headers = {
    apikey: config.publishableKey,
    'Content-Type': 'application/json',
  };

  async function post(path, body, accessToken) {
    const response = await fetchImpl(new URL(path, base), {
      method: 'POST',
      headers: accessToken
        ? { ...headers, Authorization: `Bearer ${accessToken}` }
        : headers,
      body: JSON.stringify(body),
      cache: 'no-store',
    });
    const result = await response.json().catch(() => null);
    if (!response.ok || !result || typeof result !== 'object') {
      throw new Error(`request_failed_${response.status}`);
    }
    return result;
  }

  return {
    // Existing accounts only: a deletion request must never create a user.
    requestCode: (email) =>
      post('/auth/v1/otp', { email, create_user: false }),
    async verifyCode(email, code) {
      const result = await post('/auth/v1/verify', {
        email,
        token: code,
        type: 'email',
      });
      if (typeof result.access_token !== 'string' ||
          typeof result.user?.email !== 'string' ||
          result.user.email.toLowerCase() !== email.toLowerCase()) {
        throw new Error('invalid_session');
      }
      return { accessToken: result.access_token, email: result.user.email };
    },
    async deleteAccount(session) {
      const result = await post('/functions/v1/delete-account', {
        confirmation: 'DELETE_ACCOUNT',
        email: session.email,
      }, session.accessToken);
      if (result.deleted !== true) throw new Error('deletion_unconfirmed');
    },
  };
}

if (typeof document !== 'undefined') {
  const emailForm = document.querySelector('#email-form');
  const codeForm = document.querySelector('#code-form');
  const deleteForm = document.querySelector('#delete-form');
  const status = document.querySelector('#status');
  const emailInput = document.querySelector('#email');
  const codeInput = document.querySelector('#code');
  const confirmationInput = document.querySelector('#confirmation');
  let api;
  let requestedEmail;
  let session;

  function message(value) { status.textContent = value; }
  function busy(value) {
    for (const button of document.querySelectorAll('button')) {
      button.disabled = value;
    }
  }

  try {
    if (location.protocol !== 'https:' &&
        location.hostname !== 'localhost' &&
        location.hostname !== '127.0.0.1') {
      throw new Error('insecure_page');
    }
    api = createDeletionApi(window.GROWUP_ACCOUNT_DELETE_CONFIG);
  } catch (_) {
    message('이 페이지의 계정 삭제 연결이 아직 준비되지 않았습니다.');
    emailForm.querySelector('button').disabled = true;
  }

  emailForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!api) return;
    requestedEmail = emailInput.value.trim();
    session = null;
    codeInput.value = '';
    codeForm.hidden = true;
    deleteForm.hidden = true;
    busy(true);
    let serviceUnavailable = false;
    try {
      await api.requestCode(requestedEmail);
    } catch (error) {
      // An unknown account and a sent code get the same response.
      serviceUnavailable = error instanceof TypeError ||
        /^request_failed_5\d\d$/.test(error.message);
    } finally {
      busy(false);
    }
    if (serviceUnavailable) {
      message('서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    codeForm.hidden = false;
    message('등록된 계정이라면 인증번호가 발송됩니다. 받지 못했다면 잠시 후 다시 시도해 주세요.');
    codeInput.focus();
  });

  codeForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    busy(true);
    try {
      session = await api.verifyCode(requestedEmail, codeInput.value.trim());
      emailForm.hidden = true;
      codeForm.hidden = true;
      deleteForm.hidden = false;
      message('본인 확인이 끝났습니다. 삭제 범위를 읽고 결정해 주세요.');
      confirmationInput.focus();
    } catch (_) {
      message('인증번호를 확인하지 못했어요. 번호를 다시 확인해 주세요.');
    } finally {
      busy(false);
    }
  });

  deleteForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!session || confirmationInput.value.trim() !== '탈퇴') {
      message('계속하려면 탈퇴를 정확히 입력해 주세요.');
      return;
    }
    busy(true);
    try {
      await api.deleteAccount(session);
      session = null;
      deleteForm.hidden = true;
      emailForm.hidden = true;
      message('계정과 연결된 서버 기록이 삭제됐습니다.');
    } catch (_) {
      message('삭제 결과를 확인하지 못했어요. 계정에 다시 로그인할 수 있는지 확인해 주세요.');
      busy(false);
    }
  });
}
