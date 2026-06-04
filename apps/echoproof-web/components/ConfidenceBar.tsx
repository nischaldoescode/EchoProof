"use client";

// web confidence bar component
// @params none

import { useEffect, useState } from "react";

interface ConfidenceBarProps {
  confidence: number;
  status:     string;
}

const statusColor: Record<string, string> = {
  verified:      "#4caf6e",
  controversial: "#f59e0b",
  disputed:      "#f87171",
  active:        "#4caf6e",
  default:       "#d1d5db",
};

export default function ConfidenceBar({ confidence, status }: ConfidenceBarProps) {
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const t = setTimeout(() => setWidth(confidence), 300);
    return () => clearTimeout(t);
  }, [confidence]);

  const color = statusColor[status] ?? statusColor.default;

  if (confidence === 0) {
    return (
      <span className="text-[11px] text-neutral-400 font-medium">
        awaiting signals
      </span>
    );
  }

  return (
    <div className="w-full">
      <div className="h-1.5 bg-neutral-100 rounded-full overflow-hidden">
        <div
          className="h-full rounded-full transition-all duration-700 ease-out"
          style={{ width: `${width}%`, backgroundColor: color }}
        />
      </div>
      <div className="mt-1 flex items-center justify-between">
        <span className="text-[10px] text-neutral-400">community confidence</span>
        <span
          className="text-[10px] font-semibold"
          style={{ color }}
        >
          {Math.round(confidence)}%
        </span>
      </div>
    </div>
  );
}