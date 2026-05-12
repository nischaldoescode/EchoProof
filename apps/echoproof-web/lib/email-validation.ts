const EMAIL_MAX_LENGTH = 254;
const LOCAL_MAX_LENGTH = 64;
const DOMAIN_MAX_LENGTH = 253;

export function normalizeEmail(value: string) {
  return value
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .trim()
    .toLowerCase();
}

export function validateDeletionEmail(value: string) {
  const email = normalizeEmail(value);

  if (!email) return "Enter the email on your Echoproof account.";
  if (email.length > EMAIL_MAX_LENGTH) return "Email is too long.";
  if (/[<>\s]/.test(email)) return "Email cannot contain spaces or markup.";

  const parts = email.split("@");
  if (parts.length !== 2) return "Enter a valid email address.";

  const [local, domain] = parts;
  if (!local || !domain) return "Enter a valid email address.";
  if (local.length > LOCAL_MAX_LENGTH) return "Email username is too long.";
  if (domain.length > DOMAIN_MAX_LENGTH) return "Email domain is too long.";
  if (local.startsWith(".") || local.endsWith(".") || local.includes("..")) {
    return "Email username has invalid dots.";
  }
  if (!/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/i.test(local)) {
    return "Email username has unsupported characters.";
  }

  const labels = domain.split(".");
  if (labels.length < 2) return "Email domain must include a valid ending.";
  if (labels.some((label) => label.length === 0 || label.length > 63)) {
    return "Email domain is not valid.";
  }
  if (
    labels.some(
      (label) =>
        label.startsWith("-") ||
        label.endsWith("-") ||
        !/^[a-z0-9-]+$/i.test(label),
    )
  ) {
    return "Email domain has unsupported characters.";
  }

  const tld = labels[labels.length - 1];
  if (!/^(xn--[a-z0-9-]{2,}|[a-z]{2,24})$/i.test(tld)) {
    return "Email domain ending is not valid.";
  }

  return null;
}
