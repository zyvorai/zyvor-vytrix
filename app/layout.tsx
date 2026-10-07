import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zyvor Vytrix — System intelligence",
  description: "Open-source system monitoring: grouped applications, containers, CPU, memory, disk and network telemetry.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#e7eefb" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1020" },
  ],
};

// Applies saved appearance before first paint so the window never flashes the wrong theme.
const preferenceScript = `try{var p=JSON.parse(localStorage.getItem('vytrix-preferences')||'{}'),r=document.documentElement,a=p.appearance||'auto',d=a==='dark'||(a==='auto'&&matchMedia('(prefers-color-scheme: dark)').matches);r.classList.toggle('dark',d);if(p.accent)r.dataset.accent=p.accent;if(p.reduceTransparency)r.dataset.transparency='reduced';if(p.theme==='adwaita'||p.theme==='glass')r.dataset.theme=p.theme;}catch(e){}`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-theme="glass" data-accent="blue" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: preferenceScript }} />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
