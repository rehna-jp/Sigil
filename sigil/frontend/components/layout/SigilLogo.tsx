'use client';

import Image from 'next/image';
import logoImg from '../../assets/image.png';

interface SigilLogoProps {
  size?: number;
  animate?: boolean;
  className?: string;
}

export function SigilLogo({ size = 40, animate = false, className = '' }: SigilLogoProps) {
  return (
    <Image
      src={logoImg}
      alt="Sigil logo"
      width={size}
      height={size}
      className={`${animate ? 'animate-spin-slow' : ''} ${className}`}
      priority
    />
  );
}
