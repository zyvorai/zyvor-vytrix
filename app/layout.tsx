import type { Metadata, Viewport } from "next";
import "./globals.css";

const description =
  "Read-only system activity monitor for macOS and Linux: grouped applications, processes, ports and Docker/Podman containers, in Liquid Glass or Adwaita.";
// Absolute: crawlers fetch this from outside, and there is no hosted site to resolve a relative path against.
const ogImage = "https://raw.githubusercontent.com/zyvorai/zyvor-vytrix/main/public/og.jpg";

export const metadata: Metadata = {
  title: "Zyvor Vytrix — System intelligence",
  description,
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
    apple: "/apple-touch-icon.png",
  },
  openGraph: {
    type: "website",
    siteName: "Zyvor Vytrix",
    title: "Zyvor Vytrix — See what your machine is really doing",
    description,
    images: [{ url: ogImage, width: 1200, height: 630, alt: "Zyvor Vytrix dashboard in Liquid Glass and Adwaita" }],
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
