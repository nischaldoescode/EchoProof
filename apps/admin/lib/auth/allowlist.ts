export function getAdminAllowlist() {
  return (
    process.env.ADMIN_ALLOWED_EMAILS ||
    process.env.ADMIN_EMAIL_ALLOWLIST ||
    process.env.ADMIN_EMAIL ||
    "support@echoproof.online"
  )
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}

export function hasAdminAllowlist() {
  return getAdminAllowlist().length > 0;
}

export function isAllowedAdminEmail(email?: string | null) {
  if (!email) return false;

  const normalized = email.trim().toLowerCase();
  const allowlist = getAdminAllowlist();

  if (allowlist.length === 0) {
    return process.env.NODE_ENV !== "production";
  }

  return allowlist.some((entry) => {
    if (entry.startsWith("@")) return normalized.endsWith(entry);
    return normalized === entry;
  });
}
