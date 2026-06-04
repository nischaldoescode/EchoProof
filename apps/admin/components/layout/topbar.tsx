// admin layout topbar component
// @params none

interface TopbarProps {
  title: string;
  subtitle?: string;
}

export function Topbar({ title, subtitle }: TopbarProps) {
  return (
    <header className="sticky top-0 z-10 flex min-h-14 items-center gap-3 border-b border-[#E6E6E6] bg-white/95 px-4 py-3 backdrop-blur transition-shadow duration-200 sm:px-6">
      <div className="min-w-0">
        <h1 className="truncate text-sm font-semibold text-charcoal sm:text-[15px]">
          {title}
        </h1>
        {subtitle && (
          <p className="line-clamp-2 text-xs leading-snug text-gray-400 sm:line-clamp-1">
            {subtitle}
          </p>
        )}
      </div>
    </header>
  );
}
