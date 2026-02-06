import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Noodles — Dev Server Manager for macOS",
  description:
    "A native macOS menu bar app for managing your Node.js dev servers. Start, stop, and monitor all your projects from one place.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
