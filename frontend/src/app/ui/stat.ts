import { Component, input } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { RouterLink } from '@angular/router';

import { UiIcon } from './icon';

/**
 * A single number with its label. Used for the dashboard tiles and the report
 * summaries, which were previously two different sets of markup for the same
 * idea.
 *
 * `hint` exists because a bare number invites the wrong reading — "Fees owed"
 * next to "$18.00" says nothing about whether that money has been collected.
 *
 * With `link` the whole tile is the way into the list behind the number, and a
 * chevron says so: a dashboard number that goes nowhere makes people hunt for
 * the screen that explains it.
 */
@Component({
  selector: 'ui-stat',
  imports: [NgTemplateOutlet, RouterLink, UiIcon],
  template: `
    @if (link()) {
      <a class="stat stat--link" [routerLink]="link()" [queryParams]="queryParams()">
        <ng-container *ngTemplateOutlet="body" />
        <ui-icon class="stat__go" name="chevron_right" />
      </a>
    } @else {
      <div class="stat"><ng-container *ngTemplateOutlet="body" /></div>
    }
    <ng-template #body>
      <p class="stat__label">{{ label() }}</p>
      <p class="stat__value">{{ value() }}</p>
      @if (hint()) {
        <p class="stat__hint">{{ hint() }}</p>
      }
    </ng-template>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: block;
      min-width: 0;
    }
    .stat {
      position: relative;
      display: flex;
      flex-direction: column;
      gap: var(--sp-1);
      height: 100%;
      padding: var(--sp-4);
      background: var(--md-surface-container-lowest);
      border: 1px solid var(--md-outline-variant);
      border-radius: var(--md-shape-md);
      color: inherit;
      text-decoration: none;
    }
    :host([tone='primary']) .stat {
      background: var(--md-primary-container);
      border-color: transparent;
      color: var(--md-on-primary-container);
    }
    :host([tone='attention']) .stat {
      background: var(--md-warning-container);
      border-color: transparent;
      color: var(--md-on-warning-container);
    }
    .stat--link {
      padding-right: var(--sp-6);
      cursor: pointer;
      @include focus-ring;

      &:hover {
        border-color: var(--md-primary);
      }
    }
    .stat__go {
      position: absolute;
      top: 50%;
      right: var(--sp-2);
      transform: translateY(-50%);
      color: var(--md-on-surface-variant);
    }
    .stat__label {
      @include type-label-md;
      text-transform: uppercase;
      color: var(--md-on-surface-variant);
      :host([tone]) & {
        color: inherit;
      }
    }
    .stat__value {
      @include type-headline-sm;
      font-variant-numeric: tabular-nums;
    }
    .stat__hint {
      @include type-body-sm;
      color: var(--md-on-surface-variant);
      :host([tone]) & {
        color: inherit;
      }
    }
  `,
})
export class UiStat {
  readonly label = input.required<string>();
  readonly value = input.required<string | number>();
  readonly hint = input<string | undefined>(undefined);
  /** Where the number comes from; the tile becomes a link to it. */
  readonly link = input<string | unknown[] | null>(null);
  readonly queryParams = input<Record<string, string | number> | null>(null);
}
