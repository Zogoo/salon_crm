import { Component, computed, inject, input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { LocationContextService } from '../core/services/location-context.service';
import { UiIcon } from '../ui';

/**
 * Which location a screen is showing — on the screens that depend on one, and
 * only there. A single switch in the app bar implied every screen was per
 * location, when clients and gift card look-ups span all four.
 *
 * The Owner chooses here. A Manager works at one location, so for them it is a
 * plain label: something that looks clickable but cannot change is a guess.
 */
@Component({
  selector: 'app-location-scope',
  imports: [FormsModule, UiIcon],
  template: `
    @if (canSwitch()) {
      <label class="scope" data-testid="location-scope">
        <ui-icon name="store" />
        <span class="scope__label">{{ label() }}</span>
        <select
          [ngModel]="ctx.current()?.id"
          (ngModelChange)="choose($event)"
          data-testid="location-scope-select"
        >
          @for (l of ctx.locations(); track l.id) {
            <option [ngValue]="l.id">{{ l.name }}</option>
          }
        </select>
        <ui-icon class="scope__chevron" name="expand_more" />
      </label>
    } @else if (ctx.current(); as loc) {
      <span class="scope scope--fixed" data-testid="location-scope">
        <ui-icon name="store" />
        <span class="scope__label">{{ label() }}</span>
        <strong>{{ loc.name }}</strong>
      </span>
    }
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: inline-flex;
    }

    .scope {
      position: relative;
      display: inline-flex;
      align-items: center;
      gap: var(--sp-2);
      min-height: 3rem;
      padding: 0 var(--sp-3);
      border: 1px solid var(--md-outline);
      border-radius: var(--md-shape-full);
      background: var(--md-surface-container-lowest);
      color: var(--md-on-surface-variant);
    }

    .scope__label {
      @include type-label-md;
    }

    select {
      appearance: none;
      min-height: 2.5rem;
      padding: 0 var(--sp-6) 0 0;
      border: 0;
      background: transparent;
      color: var(--md-on-surface);
      cursor: pointer;
      font: inherit;
      font-weight: 600;
      @include focus-ring;
    }

    .scope__chevron {
      position: absolute;
      right: var(--sp-3);
      pointer-events: none;
    }

    // Read-only: no border to press, no chevron to open.
    .scope--fixed {
      border-color: transparent;
      background: var(--md-surface-container-high);

      strong {
        color: var(--md-on-surface);
      }
    }
  `,
})
export class LocationScope {
  protected readonly ctx = inject(LocationContextService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly label = input('Location');
  /** Off inside a dialog, where re-opening the screen would throw the form away. */
  readonly reload = input(true);

  protected readonly canSwitch = computed(
    () => this.auth.user()?.role === 'owner' && this.ctx.locations().length > 1,
  );

  protected choose(id: number): void {
    this.ctx.select(id);
    if (!this.reload()) return;
    // Screens read the location once as they open, so the open screen is opened again.
    const url = this.router.url;
    void this.router
      .navigateByUrl('/', { skipLocationChange: true })
      .then(() => this.router.navigateByUrl(url));
  }
}
