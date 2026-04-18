interface TopbarProps {
  title: string;
  subtitle?: string;
}

export function Topbar({ title, subtitle }: TopbarProps) {
  return (
    <header className="h-14 border-b border-border-subtle bg-white flex items-center px-6 gap-3">
      <div>
        <h1 className="text-charcoal font-semibold text-sm">{title}</h1>
        {subtitle && (
          <p className="text-gray-400 text-xs">{subtitle}</p>
        )}
      </div>
    </header>
  );
}