[2mInstalled [1m126 packages[0m [2min 293ms[0m[0m
```html
<!doctype html>
<html lang="th">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>เข้าสู่ระบบ — Forward Insight</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Noto+Sans+Thai:wght@400;500;700&display=swap"
      rel="stylesheet"
    />
    <style>
      *,
      *::before,
      *::after {
        box-sizing: border-box;
        margin: 0;
        padding: 0;
      }

      :root {
        --bg-gradient-start: #0f172a;
        --bg-gradient-mid: #1e3a5f;
        --bg-gradient-end: #0e7490;
        --surface: #ffffff;
        --primary: #0e7490;
        --primary-hover: #155e75;
        --primary-disabled: #94a3b8;
        --text: #0f172a;
        --muted: #64748b;
        --border: #cbd5e1;
        --border-focus: #0e7490;
        --error: #dc2626;
        --error-bg: #fef2f2;
        --error-border: #fecaca;
        --success: #15803d;
        --success-bg: #f0fdf4;
        --radius-card: 16px;
        --radius-input: 8px;
        --radius-checkbox: 4px;
        --shadow-card: 0 20px 40px rgba(15, 23, 42, 0.25);
        --focus-ring: 0 0 0 3px rgba(14, 116, 144, 0.25);
      }

      body {
        font-family: 'Noto Sans Thai', 'Sarabun', -apple-system, 'Segoe UI',
          Roboto, sans-serif;
        line-height: 1.5;
        min-height: 100vh;
        background: linear-gradient(
          135deg,
          var(--bg-gradient-start) 0%,
          var(--bg-gradient-mid) 50%,
          var(--bg-gradient-end) 100%
        );
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 16px;
      }

      .card {
        width: 100%;
        max-width: 400px;
        background: var(--surface);
        border-radius: var(--radius-card);
        box-shadow: var(--shadow-card);
        padding: 32px;
      }

      .header {
        display: flex;
        flex-direction: column;
        align-items: center;
        margin-bottom: 24px;
      }

      .logo {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        background: var(--primary);
        color: #ffffff;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 24px;
        font-weight: 700;
        margin-bottom: 16px;
      }

      .heading {
        font-size: 24px;
        font-weight: 700;
        color: var(--text);
        text-align: center;
      }

      .subheading {
        font-size: 14px;
        font-weight: 400;
        color: var(--muted);
        text-align: center;
        margin-top: 8px;
      }

      .error-banner {
        display: none;
        background: var(--error-bg);
        border: 1px solid var(--error-border);
        color: var(--error);
        padding: 12px;
        border-radius: var(--radius-input);
        font-size: 14px;
        margin-bottom: 16px;
      }

      .error-banner.is-visible {
        display: block;
      }

      .form {
        display: flex;
        flex-direction: column;
      }

      .field {
        display: flex;
        flex-direction: column;
        margin-bottom: 16px;
      }

      .field:last-of-type {
        margin-bottom: 0;
      }

      .label {
        font-size: 14px;
        font-weight: 500;
        color: var(--text);
        margin-bottom: 8px;
      }

      .input-wrapper {
        position: relative;
      }

      .input {
        width: 100%;
        height: 48px;
        padding: 0 14px;
        font-family: inherit;
        font-size: 16px;
        font-weight: 400;
        color: var(--text);
        background: #ffffff;
        border: 1px solid var(--border);
        border-radius: var(--radius-input);
        outline: none;
        transition: border-color 0.15s ease, box-shadow 0.15s ease;
      }

      .input[type='password'] {
        padding-right: 48px;
      }

      .input::placeholder {
        color: var(--muted);
      }

      .input:focus {
        border-color: var(--border-focus);
        box-shadow: var(--focus-ring);
      }

      .input.is-invalid {
        border-color: var(--error);
      }

      .input.is-invalid:focus {
        box-shadow: 0 0 0 3px rgba(220, 38, 38, 0.25);
      }

      .toggle-password {
        position: absolute;
        top: 50%;
        right: 4px;
        transform: translateY(-50%);
        width: 40px;
        height: 40px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: transparent;
        border: none;
        cursor: pointer;
        color: var(--muted);
        border-radius: var(--radius-input);
      }

      .toggle-password:hover {
        color: var(--text);
      }

      .toggle-password:focus-visible {
        outline: none;
        box-shadow: var(--focus-ring);
      }

      .toggle-password svg {
        width: 20px;
        height: 20px;
      }

      .field-error {
        display: none;
        font-size: 13px;
        font-weight: 400;
        color: var(--error);
        margin-top: 4px;
      }

      .field-error.is-visible {
        display: block;
      }

      .row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-top: 12px;
      }

      .checkbox-wrapper {
        display: flex;
        align-items: center;
        gap: 8px;
        cursor: pointer;
      }

      .checkbox {
        width: 18px;
        height: 18px;
        accent-color: var(--primary);
        border-radius: var(--radius-checkbox);
        cursor: pointer;
      }

      .checkbox-label {
        font-size: 14px;
        color: var(--text);
        cursor: pointer;
        user-select: none;
      }

      .link {
        font-size: 14px;
        color: var(--primary);
        text-decoration: none;
        border-radius: 4px;
      }

      .link:hover {
        text-decoration: underline;
      }

      .link:focus-visible {
        outline: none;
        box-shadow: var(--focus-ring);
      }

      .submit {
        width: 100%;
        height: 48px;
        margin-top: 24px;
        font-family: inherit;
        font-size: 16px;
        font-weight: 500;
        color: #ffffff;
        background: var(--primary);
        border: none;
        border-radius: var(--radius-input);
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        transition: background 0.15s ease, transform 0.05s ease;
      }

      .submit:hover:not(:disabled) {
        background: var(--primary-hover);
      }

      .submit:active:not(:disabled) {
        transform: translateY(1px);
      }

      .submit:focus-visible {
        outline: none;
        box-shadow: var(--focus-ring);
      }

      .submit:disabled {
        background: var(--primary-disabled);
        cursor: not-allowed;
      }

      .spinner {
        display: none;
        width: 18px;
        height: 18px;
        border: 2px solid rgba(255, 255, 255, 0.3);
        border-top-color: #ffffff;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
      }

      .submit.is-loading .spinner {
        display: inline-block;
      }

      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }

      .footer {
        text-align: center;
        margin-top: 24px;
        font-size: 14px;
        color: var(--muted);
      }

      .success-view {
        display: none;
        flex-direction: column;
        align-items: center;
        text-align: center;
      }

      .success-view.is-visible {
        display: flex;
      }

      .success-icon {
        width: 56px;
        height: 56px;
        border-radius: 50%;
        background: var(--success-bg);
        color: var(--success);
        display: flex;
        align-items: center;
        justify-content: center;
        margin-bottom: 16px;
      }

      .success-icon svg {
        width: 28px;
        height: 28px;
      }

      .success-title {
        font-size: 20px;
        font-weight: 700;
        color: var(--text);
        margin-bottom: 8px;
      }

      .success-message {
        font-size: 14px;
        color: var(--muted);
      }

      .is-hidden {
        display: none !important;
      }

      @media (max-width: 360px) {
        .card {
          padding: 20px;
        }
      }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="header">
        <div class="logo" aria-hidden="true">F</div>
        <h1 class="heading">Forward Insight</h1>
        <p class="subheading">เข้าสู่ระบบเพื่อใช้งาน</p>
      </div>

      <div id="errorBanner" class="error-banner" role="alert">
        อีเมลหรือรหัสผ่านไม่ถูกต้อง
      </div>

      <form id="loginForm" class="form" novalidate>
        <div class="field">
          <label for="email" class="label">อีเมล</label>
          <input
            id="email"
            name="email"
            type="email"
            class="input"
            placeholder="you@example.com"
            autocomplete="email"
          />
          <span id="emailError" class="field-error">
            กรุณากรอกอีเมลให้ถูกต้อง
          </span>
        </div>

        <div class="field">
          <label for="password" class="label">รหัสผ่าน</label>
          <div class="input-wrapper">
            <input
              id="password"
              name="password"
              type="password"
              class="input"
              placeholder="อย่างน้อย 8 ตัวอักษร"
              autocomplete="current-password"
            />
            <button
              id="togglePassword"
              type="button"
              class="toggle-password"
              aria-label="แสดงรหัสผ่าน"
            >
              <svg
                id="eyeIcon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
                <circle cx="12" cy="12" r="3"></circle>
              </svg>
              <svg
                id="eyeOffIcon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
                style="display: none"
              >
                <path
                  d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"
                ></path>
                <line x1="1" y1="1" x2="23" y2="23"></line>
              </svg>
            </button>
          </div>
          <span id="passwordError" class="field-error">
            รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร
          </span>
        </div>

        <div class="row">
          <label class="checkbox-wrapper">
            <input
              id="rememberMe"
              name="rememberMe"
              type="checkbox"
              class="checkbox"
            />
            <span class="checkbox-label">จดจำฉัน</span>
          </label>
          <a href="#" class="link">ลืมรหัสผ่าน?</a>
        </div>

        <button id="submitButton" type="submit" class="submit">
          <span class="spinner" aria-hidden="true"></span>
          <span id="submitText">เข้าสู่ระบบ</span>
        </button>
      </form>

      <div id="successView" class="success-view">
        <div class="success-icon">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="3"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <polyline points="20 6 9 17 4 12"></polyline>
          </svg>
        </div>
        <h2 class="success-title">เข้าสู่ระบบสำเร็จ</h2>
        <p id="successMessage" class="success-message">
          ยินดีต้อนรับกลับมา คุณ demo@example.com
        </p>
      </div>

      <p class="footer">
        ยังไม่มีบัญชี? <a href="#" class="link">สมัครสมาชิก</a>
      </p>
    </main>

    <script>
      (function () {
        const form = document.getElementById('loginForm');
        const emailInput = document.getElementById('email');
        const passwordInput = document.getElementById('password');
        const emailError = document.getElementById('emailError');
        const passwordError = document.getElementById('passwordError');
        const errorBanner = document.getElementById('errorBanner');
        const togglePassword = document.getElementById('togglePassword');
        const eyeIcon = document.getElementById('eyeIcon');
        const eyeOffIcon = document.getElementById('eyeOffIcon');
        const submitButton = document.getElementById('submitButton');
        const submitText = document.getElementById('submitText');
        const successView = document.getElementById('successView');
        const successMessage = document.getElementById('successMessage');

        const mockEmail = 'demo@example.com';
        const mockPassword = 'password123';
        const networkDelay = 1000;

        function isValidEmail(value) {
          const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
          return emailPattern.test(value);
        }

        function clearFieldError(input, error) {
          input.classList.remove('is-invalid');
          error.classList.remove('is-visible');
        }

        function showFieldError(input, error) {
          input.classList.add('is-invalid');
          error.classList.add('is-visible');
        }

        function clearAllFieldErrors() {
          clearFieldError(emailInput, emailError);
          clearFieldError(passwordInput, passwordError);
        }

        function hideErrorBanner() {
          errorBanner.classList.remove('is-visible');
        }

        function showErrorBanner() {
          errorBanner.classList.add('is-visible');
        }

        function setLoading(isLoading) {
          submitButton.disabled = isLoading;
          submitButton.classList.toggle('is-loading', isLoading);
          emailInput.disabled = isLoading;
          passwordInput.disabled = isLoading;
          submitText.textContent = isLoading
            ? 'กำลังเข้าสู่ระบบ…'
            : 'เข้าสู่ระบบ';
        }

        function validateForm() {
          clearAllFieldErrors();
          hideErrorBanner();

          const email = emailInput.value.trim();
          const password = passwordInput.value;
          let isValid = true;
          let firstInvalid = null;

          if (!email || !isValidEmail(email)) {
            showFieldError(emailInput, emailError);
            isValid = false;
            firstInvalid = firstInvalid || emailInput;
          }

          if (!password || password.length < 8) {
            showFieldError(passwordInput, passwordError);
            isValid = false;
            firstInvalid = firstInvalid || passwordInput;
          }

          if (firstInvalid) {
            firstInvalid.focus();
          }

          return isValid;
        }

        function handleSubmit(event) {
          event.preventDefault();

          if (!validateForm()) {
            return;
          }

          setLoading(true);
          hideErrorBanner();

          const email = emailInput.value.trim();
          const password = passwordInput.value;

          setTimeout(function () {
            setLoading(false);

            if (email === mockEmail && password === mockPassword) {
              form.classList.add('is-hidden');
              successMessage.textContent =
                'ยินดีต้อนรับกลับมา คุณ ' + email;
              successView.classList.add('is-visible');
            } else {
              showErrorBanner();
              passwordInput.focus();
            }
          }, networkDelay);
        }

        function handlePasswordToggle() {
          const isPassword = passwordInput.type === 'password';
          passwordInput.type = isPassword ? 'text' : 'password';
          togglePassword.setAttribute(
            'aria-label',
            isPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'
          );
          eyeIcon.style.display = isPassword ? 'none' : 'block';
          eyeOffIcon.style.display = isPassword ? 'block' : 'none';
        }

        emailInput.addEventListener('input', function () {
          if (emailInput.classList.contains('is-invalid')) {
            clearFieldError(emailInput, emailError);
          }
        });

        passwordInput.addEventListener('input', function () {
          if (passwordInput.classList.contains('is-invalid')) {
            clearFieldError(passwordInput, passwordError);
          }
        });

        togglePassword.addEventListener('click', handlePasswordToggle);
        form.addEventListener('submit', handleSubmit);
      })();
    </script>
  </body>
</html>
```

To resume this session: kimi -r da0f748d-1a79-4e3f-9e5b-7cbe0909f39f

