const rawAdminBasePath =
  process.env.NEXT_PUBLIC_ADMIN_BASE_PATH || process.env.ADMIN_BASE_PATH || "";

export const adminBasePath = normalizeBasePath(rawAdminBasePath);

export function adminPath(path = "/") {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  if (!adminBasePath) return normalizedPath;
  if (normalizedPath === "/") return adminBasePath;
  return `${adminBasePath}${normalizedPath}`;
}

function normalizeBasePath(value: string) {
  const trimmed = value.trim();
  if (!trimmed || trimmed === "/") return "";

  const withSlash = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return withSlash.replace(/\/+$/, "");
}
