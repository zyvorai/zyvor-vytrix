'use client';
// SPDX-License-Identifier: Apache-2.0
import {type ReactNode} from 'react';
import {Sheet,SheetContent,SheetTitle} from '@/components/ui/sheet';

export function AppShell({sidebar,toolbar,children,footer,sidebarOpen,mobileNavOpen,onMobileNavChange}:{sidebar:ReactNode,toolbar:ReactNode,children:ReactNode,footer:ReactNode,sidebarOpen:boolean,mobileNavOpen:boolean,onMobileNavChange:(open:boolean)=>void}){
  return <div className="wallpaper">
    <div className="window glass" data-sidebar={sidebarOpen?'open':'closed'}>
      <aside className="sidebar glass">{sidebar}</aside>
      <div className="main">
        {toolbar}
        <main className="content" id="content">{children}</main>
        {footer}
      </div>
    </div>
    <Sheet open={mobileNavOpen} onOpenChange={onMobileNavChange}>
      <SheetContent side="left" className="glass-sheet mobile-nav" showCloseButton={false}>
        <SheetTitle className="sr-only">Navigation</SheetTitle>
        {sidebar}
      </SheetContent>
    </Sheet>
  </div>;
}
