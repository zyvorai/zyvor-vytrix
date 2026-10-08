import type { Metadata, Viewport } from "next";
import "./globals.css";

// Empty except for the GitHub Pages demo build (see next.config.ts). Metadata icon URLs are not prefixed
// automatically, so they carry the base path themselves.
const base = process.env.VYTRIX_BASE_PATH || "";
const description =
  "Read-only system activity monitor for macOS and Linux: grouped applications, processes, ports and Docker/Podman containers, in Liquid Glass or Adwaita.";
// Absolute: crawlers fetch this from outside the page. It is the hero published with the GitHub Pages site.
const ogImage = "https://zyvorai.github.io/zyvor-vytrix/social/vytrix-hero-dark.jpg";

export const metadata: Metadata = {
  title: "Zyvor Vytrix — System intelligence",
  description,
  icons: {
    icon: `${base}/favicon.svg`,
    shortcut: `${base}/favicon.svg`,
    apple: `${base}/apple-touch-icon.png`,
  },
  openGraph: {
    type: "website",
    siteName: "Zyvor Vytrix",
    title: "Zyvor Vytrix — See what your machine is really doing",
    description,
    images: [{ url: ogImage, width: 2400, height: 1260, alt: "Zyvor Vytrix dashboard in Liquid Glass and Adwaita" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Zyvor Vytrix — See what your machine is really doing",
    description,
    images: [ogImage],
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#e7eefb" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1020" },
  ],
};

// Applies saved appearance before first paint so the window never flashes the wrong theme.
const preferenceScript = `try{var p=JSON.parse(localStorage.getItem('vytrix-preferences')||'{}'),r=document.documentElement,a=p.appearance||'auto',d=a==='dark'||(a==='auto'&&matchMedia('(prefers-color-scheme: dark)').matches);r.classList.toggle('dark',d);if(p.accent)r.dataset.accent=p.accent;if(p.reduceTransparency)r.dataset.transparency='reduced';if(p.theme==='adwaita'||p.theme==='glass'||p.theme==='macos27')r.dataset.theme=p.theme;}catch(e){}`;

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
