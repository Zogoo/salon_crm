import { Component, input } from '@angular/core';

import { UiIcon } from './icon';

/**
 * An empty list should say why it is empty and what to do next, rather than
 * leaving the reader to work out whether it is broken or simply empty.
 */
@Component({
  selector: 'ui-empty',
  imports: [UiIcon],
  template: `
    <div class="empty">
      <ui-icon [name]="icon()" class="empty__icon" />
      <p class="empty__title">{{ title() }}</p>
      @if (hint()) {
        <p class="empty__hint">{{ hint() }}</p>
      }
      <ng-content />
    </div>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    .empty {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      gap: var(--sp-2);
      padding: var(--sp-6) var(--sp-4);
      color: var(--md-on-surface-variant);
    }
    .empty__icon {
      --size: 40px;
      color: var(--md-outline);
    }
    .empty__title {
      @include type-title-sm;
      color: var(--md-on-surface);
    }
    .empty__hint {
      @include type-body-sm;
      max-width: 44ch;
    }
  `,
})
export class UiEmpty {
  readonly icon = input('inbox');
  readonly title = input.required<string>();
  readonly hint = input<string | undefined>(undefined);
}
