import { Component, OnInit, computed, effect, inject, signal, untracked } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';

import { NavBadge, groupsFor } from './core/navigation';
import { todayIn } from './core/salon-date';
import { AuthService } from './core/services/auth.service';
import { LocationContextService } from './core/services/location-context.service';
import { MassagelabService } from './core/services/massagelab.service';
import { UiButton, UiConfirmHost, UiIcon } from './ui';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, UiIcon, UiButton, UiConfirmHost],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly api = inject(MassagelabService);
  protected readonly locations = inject(LocationContextService);

  /** How much is waiting behind each badged link. */
  protected readonly badges = signal<Partial<Record<NavBadge, number>>>({});

  protected readonly ready = signal(false);
  protected readonly user = this.auth.user;
  protected readonly groups = computed(() => groupsFor(this.user()?.role));

  /** Open only on compact screens; the drawer is permanent above 1024px. */
  protected readonly drawerOpen = signal(false);

  /**
   * The rating kiosk sits unattended on a screen in a public room, so it must
   * not offer a way into the rest of the console.
   */
  protected readonly bare = signal(false);

  /** Only the desk can create a booking (BR-14), so only they get the action. */
  protected readonly canBook = computed(() => this.user()?.role !== 'staff');

  constructor() {
    // Count as soon as both who is signed in and where are known — after a
    // fresh sign-in that is later than the first navigation.
    effect(() => {
      if (this.user() && this.locations.current()) untracked(() => this.refreshBadges());
    });
  }

  ngOnInit(): void {
    this.applyChrome(this.router.url);
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => {
        this.applyChrome(e.urlAfterRedirects);
        // A tapped link on a phone should reveal the page, not leave the
        // drawer covering it.
        this.drawerOpen.set(false);
        // Counts follow the work: approving or reviewing changes them.
        this.refreshBadges();
      });

    if (!this.auth.token) {
      this.ready.set(true);
      return;
    }

    this.auth.loadCurrentUser().subscribe({
      next: () => {
        this.ready.set(true);
        void this.locations.load().then(() => this.refreshBadges());
      },
      error: () => this.ready.set(true),
    });
  }

  protected toggleDrawer(): void {
    this.drawerOpen.update((v) => !v);
  }

  protected signOut(): void {
    this.auth.signOut();
    this.locations.clear();
    void this.router.navigate(['/sign-in']);
  }

  /** Only the desk reviews, so only the desk is counted for. */
  private refreshBadges(): void {
    const role = this.user()?.role;
    const loc = this.locations.current();
    if (!role || role === 'staff' || !loc || this.bare()) return;
    this.api.dashboard(loc.id, todayIn(loc.timezone)).subscribe({
      next: (d) => this.badges.update((b) => ({ ...b, approvals: d.pending_approvals })),
    });
    this.api.staffRequests({ status: 'submitted', limit: 1 }).subscribe({
      next: ({ meta }) => this.badges.update((b) => ({ ...b, staffRequests: meta.count })),
    });
  }

  private applyChrome(url: string): void {
    this.bare.set(
      url.startsWith('/kiosk') ||
        url.startsWith('/sign-in') ||
        url.startsWith('/rate/') ||
        url.startsWith('/reset-password/'),
    );
  }
}
