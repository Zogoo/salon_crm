import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { filter } from 'rxjs';

import { groupsFor } from './core/navigation';
import { AuthService } from './core/services/auth.service';
import { LocationContextService } from './core/services/location-context.service';
import { UiButton, UiIcon } from './ui';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, FormsModule, UiIcon, UiButton],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly locations = inject(LocationContextService);

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

  ngOnInit(): void {
    this.applyChrome(this.router.url);
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => {
        this.applyChrome(e.urlAfterRedirects);
        // A tapped link on a phone should reveal the page, not leave the
        // drawer covering it.
        this.drawerOpen.set(false);
      });

    if (!this.auth.token) {
      this.ready.set(true);
      return;
    }

    this.auth.loadCurrentUser().subscribe({
      next: () => {
        this.ready.set(true);
        void this.locations.load();
      },
      error: () => this.ready.set(true),
    });
  }

  protected toggleDrawer(): void {
    this.drawerOpen.update((v) => !v);
  }

  protected onLocationChange(id: number): void {
    this.locations.select(id);
    // Screens read the location from the shared context, so a change has to
    // reach the one currently open.
    const url = this.router.url;
    void this.router.navigateByUrl('/', { skipLocationChange: true }).then(() => {
      void this.router.navigateByUrl(url);
    });
  }

  protected signOut(): void {
    this.auth.signOut();
    this.locations.clear();
    void this.router.navigate(['/sign-in']);
  }

  private applyChrome(url: string): void {
    this.bare.set(url.startsWith('/kiosk') || url.startsWith('/sign-in') || url.startsWith('/sign-up'));
  }
}
