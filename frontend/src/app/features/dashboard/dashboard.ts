import { Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';

import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-dashboard',
  imports: [RouterLink, TranslatePipe],
  template: `
    <section class="card">
      <h1>{{ 'dashboard.title' | translate }}</h1>

      @if (user(); as currentUser) {
        <p>{{ 'dashboard.greeting' | translate: { name: currentUser.name } }}</p>
      }

      <p>{{ 'dashboard.intro' | translate }}</p>
      <a routerLink="/notes">{{ 'dashboard.go_to_notes' | translate }}</a>
    </section>
  `,
})
export class Dashboard {
  protected readonly user = inject(AuthService).user;
}
