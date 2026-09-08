import { Component, OnInit, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { TranslatePipe } from '@ngx-translate/core';

import { AuthService } from './core/services/auth.service';
import { LocationContextService } from './core/services/location-context.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly locations = inject(LocationContextService);

  protected readonly ready = signal(false);
  protected readonly user = this.auth.user;

  /**
   * The rating kiosk sits unattended on a screen in a public room, so it must
   * not offer a way into the rest of the console. Hiding the chrome is the
   * cheap half of that; the bare route is the other half.
   */
  protected readonly bare = signal(false);

  ngOnInit(): void {
    this.bare.set(this.router.url.startsWith('/kiosk'));
    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => this.bare.set(e.urlAfterRedirects.startsWith('/kiosk')));

    // Restore the session before the first render so guards see a real user.
    if (!this.auth.token) {
      this.ready.set(true);
      return;
    }

    this.auth.loadCurrentUser().subscribe({
      next: () => this.ready.set(true),
      error: () => this.ready.set(true),
    });
  }

  protected signOut(): void {
    this.auth.signOut();
    this.locations.clear();
    void this.router.navigate(['/sign-in']);
  }
}
