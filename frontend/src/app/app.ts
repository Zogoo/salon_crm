import { Component, OnInit, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterOutlet } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';

import { AuthService } from './core/services/auth.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, TranslatePipe],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly ready = signal(false);
  protected readonly user = this.auth.user;

  ngOnInit(): void {
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
    void this.router.navigate(['/sign-in']);
  }
}
