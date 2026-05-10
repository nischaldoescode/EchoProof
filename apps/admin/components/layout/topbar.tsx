interface TopbarProps {
  title: string;
  subtitle?: string;
}

export function Topbar({ title, subtitle }: TopbarProps) {
  return (
    <header className="min-h-14 border-b border-[#E6E6E6] bg-white flex items-center px-4 py-3 sm:px-6 gap-3 sticky top-0 z-10">
      <div className="min-w-0">
        <h1 className="text-charcoal font-semibold text-sm">{title}</h1>
        {subtitle && <p className="text-gray-400 text-xs leading-snug">{subtitle}</p>}
      </div>
    </header>
  );
}
