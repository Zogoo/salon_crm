import { Component, input, output } from '@angular/core';

import { UiButton } from './button';

/**
 * A detail panel: a bottom sheet on a phone, a side panel on a wide screen.
 *
 * It is a dialog in both forms, so it traps the reader's attention on one
 * record and always offers a visible way out — tapping the scrim or the close
 * button. Screens project their own content; this owns the shell and the
 * dismissal, which is the part that must behave identically everywhere.
 */
@Component({
  selector: 'ui-sheet',
  imports: [UiButton],
  template: `
    <div class="scrim" (click)="closed.emit()"></div>
    <aside class="panel" role="dialog" aria-modal="true" [attr.aria-label]="heading()">
      <header class="panel__head">
        <div class="panel__titles">
          <h2 class="panel__title">{{ heading() }}</h2>
          @if (sub()) {
            <p class="panel__sub">{{ sub() }}</p>
          }
        </div>
        <ng-content select="[sheetBadge]" />
        <ui-button variant="text" icon="close" (click)="closed.emit()" ariaLabel="Close" />
      </header>
      <div class="panel__body"><ng-content /></div>
    </aside>
  `,
  styleUrl: './sheet.scss',
})
export class UiSheet {
  readonly heading = input.required<string>();
  readonly sub = input<string | undefined>(undefined);
  readonly closed = output<void>();
}
