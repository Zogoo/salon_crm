import { Component, input, output } from '@angular/core';

import { UiButton } from './button';

let nextId = 0;

/**
 * A modal for a short, self-contained task — create a client, edit contact
 * details, enrol a member — so the list behind it keeps its place, filters and
 * page. Actions are projected into one footer, primary on the right.
 */
@Component({
  selector: 'ui-dialog',
  imports: [UiButton],
  host: { '(keydown.escape)': 'closed.emit()' },
  template: `
    <div class="scrim" (click)="closed.emit()"></div>
    <section
      class="dialog"
      [class.dialog--wide]="size() === 'lg'"
      role="dialog"
      aria-modal="true"
      [attr.aria-labelledby]="titleId"
    >
      <header class="dialog__head">
        <div class="dialog__titles">
          <h2 [id]="titleId" class="dialog__title">{{ heading() }}</h2>
          @if (sub()) {
            <p class="dialog__sub">{{ sub() }}</p>
          }
        </div>
        <ui-button variant="text" icon="close" ariaLabel="Close" (click)="closed.emit()" />
      </header>
      <div class="dialog__body"><ng-content /></div>
      <footer class="dialog__actions"><ng-content select="[dialogActions]" /></footer>
    </section>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      position: fixed;
      inset: 0;
      z-index: 50;
      display: grid;
      place-items: center;
      padding: var(--sp-4);
    }
    .scrim {
      position: absolute;
      inset: 0;
      background: rgb(0 0 0 / 0.4);
    }
    .dialog {
      position: relative;
      display: flex;
      flex-direction: column;
      width: min(34rem, 100%);
      max-height: calc(100vh - 2 * var(--sp-4));
      border-radius: var(--md-shape-xl);
      background: var(--md-surface-container-lowest);
      box-shadow: var(--md-elev-3);
      overflow: hidden;
    }
    .dialog--wide {
      width: min(52rem, 100%);
    }
    .dialog__head {
      display: flex;
      align-items: flex-start;
      gap: var(--sp-2);
      padding: var(--sp-5) var(--sp-5) var(--sp-3);
    }
    .dialog__titles {
      flex: 1;
      min-width: 0;
    }
    .dialog__title {
      @include type-headline-sm;
    }
    .dialog__sub {
      @include type-body-sm;
      margin-top: var(--sp-1);
      color: var(--md-on-surface-variant);
    }
    .dialog__body {
      display: flex;
      flex-direction: column;
      gap: var(--sp-4);
      padding: var(--sp-2) var(--sp-5) var(--sp-4);
      overflow-y: auto;
    }
    .dialog__actions {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      gap: var(--sp-2);
      padding: var(--sp-3) var(--sp-5);
      border-top: 1px solid var(--md-outline-variant);
    }
  `,
})
export class UiDialog {
  readonly heading = input.required<string>();
  readonly sub = input<string | undefined>(undefined);
  readonly size = input<'md' | 'lg'>('md');
  readonly closed = output<void>();
  protected readonly titleId = `ui-dialog-${++nextId}`;
}
