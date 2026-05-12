export default function Footer() {
  return (
    <footer className="border-t border-neutral-100 bg-white">
      <div className="max-w-5xl mx-auto px-6 py-12">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-8">
          {/* brand */}
          <div>
            <div className="flex items-center gap-2 mb-3">
              <div className="w-7 h-7 rounded-lg overflow-hidden ring-1 ring-black/5">
                <img
                  src="/logo.png"
                  alt="Echoproof"
                  className="w-full h-full object-cover"
                />
              </div>
              <span className="font-semibold text-sm tracking-tight">
                Echoproof
              </span>
            </div>
            <p className="text-xs text-neutral-400 max-w-[50] leading-5">
              truth, verified by community.
            </p>
          </div>

          {/* links */}
          <div className="flex flex-wrap gap-x-8 gap-y-3">
            {[
              { label: "Privacy", href: "/privacy" },
              { label: "Delete account", href: "/delete-account" },
              { label: "Contact", href: "mailto:support@echoproof.online" },
            ].map((link) => (
              <a
                key={link.label}
                href={link.href}
                className="text-xs text-neutral-400 hover:text-neutral-700 transition-colors"
              >
                {link.label}
              </a>
            ))}
          </div>
        </div>

        <div className="mt-10 pt-6 border-t border-neutral-50 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-2">
          <p className="text-xs text-neutral-300">
            © {new Date().getFullYear()} Echoproof. All rights reserved.
          </p>
          <p className="text-xs text-neutral-300">Made with intention.</p>
        </div>
      </div>
    </footer>
  );
}
