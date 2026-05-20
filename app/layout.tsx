import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Reality Survival Analysis Laboratory',
  description: 'Study everything about survival',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh">
      <body>{children}</body>
    </html>
  );
}
