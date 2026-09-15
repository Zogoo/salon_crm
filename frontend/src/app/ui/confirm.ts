import {
  Component,
  ElementRef,
  Injectable,
  computed,
  effect,
  inject,
  signal,
  viewChildren,
} from '@angular/core';
import { FormsModule } from '@angular/forms';

import { UiButton } from './button';

export interface ConfirmField {
  label: string;
  type?: 'text' | 'number' | 'textarea' | 'date';
  hint?: string;
  placeholder?: string;
  required?: boolean;
  initial?: string;
  min?: number;
  max?: number;
}

export interface ConfirmOptions {
  title: string;
  /** Say what will happen and whether it can be undone — never just "Are you sure?". */
  message?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'primary' | 'danger';
  /** One answer to collect, returned as `value`. */
  field?: ConfirmField;
  /** Several answers, returned in `values` by key (e.g. a refund's amount and reason). */
  fields?: (ConfirmField & { key: string })[];
}

export interface ConfirmResult {
  confirmed: boolean;
  /** The single field's answer, or the first field's. */
  value: string;
  values: Record<string, string>;
}

type Pending = ConfirmOptions & { resolve: (result: ConfirmResult) => void };

const CANCELLED: ConfirmResult = { confirmed: false, value: '', values: {} };

/**
 * One way to ask before doing something that matters: void a payment, refund,
 * merge two clients, offboard someone. Replaces `window.prompt`, which cannot
 * be styled, explains nothing and cannot validate what is typed.
 *
 *   if (await confirm.confirm({ title: 'Remove this shift?', tone: 'danger', ... })) …
 *   const { confirmed, values } = await confirm.ask({ ..., fields: [{ key: 'reason', label: 'Reason', required: true }] });
 */
@Injectable({ providedIn: 'root' })
export class ConfirmService {
  readonly pending = signal<Pending | null>(null);

  ask(options: ConfirmOptions): Promise<ConfirmResult> {
    return new Promise((resolve) => {
      // A second request replaces an unanswered first one, which counts as cancelled.
      this.pending()?.resolve(CANCELLED);
      this.pending.set({ ...options, resolve });
    });
  }

  async confirm(options: ConfirmOptions): Promise<boolean> {
    return (await this.ask(options)).confirmed;
  }

  settle(result: ConfirmResult): void {
    const pending = this.pending();
    this.pending.set(null);
    pending?.resolve(result);
  }
}

/** Rendered once, in the app shell. */
@Component({
  selector: 'ui-confirm-host',
  imports: [FormsModule, UiButton],
  template: `
    @if (service.pending(); as p) {
      <div class="scrim" (click)="cancel()"></div>
      <section
        class="dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        aria-describedby="confirm-message"
        (keydown.escape)="cancel()"
        data-testid="confirm-dialog"
      >
        <h2 id="confirm-title" class="dialog__title">{{ p.title }}</h2>
        @if (p.message) {
          <p id="confirm-message" class="dialog__message">{{ p.message }}</p>
        }
        @for (f of fields(); track f.key; let first = $first) {
          <label class="dialog__field">
            <span class="dialog__label">
              {{ f.label }}
              @if (!f.required) {
                <span class="dialog__optional">optional</span>
              }
            </span>
            @if (f.type === 'textarea') {
              <textarea
                #input
                rows="3"
                [ngModel]="values()[f.key]"
                (ngModelChange)="setValue(f.key, $event)"
                [placeholder]="f.placeholder ?? ''"
                [attr.data-testid]="first ? 'confirm-input' : 'confirm-input-' + f.key"
              ></textarea>
            } @else {
              <input
                #input
                [type]="f.type ?? 'text'"
                [attr.min]="f.min ?? null"
                [attr.max]="f.max ?? null"
                step="any"
                [ngModel]="values()[f.key]"
                (ngModelChange)="setValue(f.key, $event)"
                [placeholder]="f.placeholder ?? ''"
                (keydown.enter)="accept()"
                [attr.data-testid]="first ? 'confirm-input' : 'confirm-input-' + f.key"
              />
            }
            @if (f.hint) {
              <span class="dialog__hint">{{ f.hint }}</span>
            }
          </label>
        }
        <footer class="dialog__actions">
          <ui-button variant="text" (click)="cancel()" data-testid="confirm-cancel">
            {{ p.cancelLabel ?? 'Cancel' }}
          </ui-button>
          <ui-button
            [variant]="p.tone === 'danger' ? 'danger' : 'filled'"
            [disabled]="!valid()"
            (click)="accept()"
            data-testid="confirm-accept"
          >
            {{ p.confirmLabel ?? 'Confirm' }}
          </ui-button>
        </footer>
      </section>
    }
  `,
  styles: `
    @use '../../styles/tokens' as *;

    .scrim {
      position: fixed;
      inset: 0;
      z-index: 60;
      background: rgb(0 0 0 / 0.4);
    }
    .dialog {
      position: fixed;
      z-index: 61;
      top: 50%;
      left: 50%;
      width: min(28rem, calc(100vw - 2 * var(--sp-4)));
      transform: translate(-50%, -50%);
      display: flex;
      flex-direction: column;
      gap: var(--sp-3);
      padding: var(--sp-5);
      border-radius: var(--md-shape-xl);
      background: var(--md-surface-container-high);
      box-shadow: var(--md-elev-3);
    }
    .dialog__title {
      @include type-headline-sm;
    }
    .dialog__message {
      @include type-body-md;
      color: var(--md-on-surface-variant);
    }
    .dialog__field {
      display: flex;
      flex-direction: column;
      gap: var(--sp-1);
      input,
      textarea {
        width: 100%;
        min-height: 3rem;
        padding: var(--sp-2) var(--sp-3);
        border: 1px solid var(--md-outline);
        border-radius: var(--md-shape-xs);
        background: var(--md-surface);
        color: var(--md-on-surface);
        font: inherit;
      }
    }
    .dialog__label {
      @include type-label-lg;
    }
    .dialog__optional,
    .dialog__hint {
      @include type-body-sm;
      color: var(--md-on-surface-variant);
    }
    .dialog__actions {
      display: flex;
      justify-content: flex-end;
      gap: var(--sp-2);
      margin-top: var(--sp-2);
    }
  `,
})
export class UiConfirmHost {
  protected readonly service = inject(ConfirmService);
  protected readonly values = signal<Record<string, string>>({});
  private readonly inputs = viewChildren<ElementRef<HTMLElement>>('input');
  private readonly host = inject(ElementRef<HTMLElement>);

  protected readonly fields = computed(() => {
    const p = this.service.pending();
    if (!p) return [];
    return p.fields ?? (p.field ? [{ key: 'value', ...p.field }] : []);
  });

  /** Required answers must be given; numbers must be positive and within bounds. */
  protected readonly valid = computed(() =>
    this.fields().every((f) => {
      const raw = (this.values()[f.key] ?? '').toString().trim();
      if (!raw) return !f.required;
      if (f.type !== 'number') return true;
      const n = Number(raw);
      return Number.isFinite(n) && n > 0 && (f.max === undefined || n <= f.max);
    }),
  );

  constructor() {
    // Start where the answer goes: the first field if there is one, else the button.
    effect(() => {
      if (!this.service.pending()) return;
      this.values.set(Object.fromEntries(this.fields().map((f) => [f.key, f.initial ?? ''])));
      setTimeout(() => {
        const first = this.inputs()[0]?.nativeElement;
        const button = (this.host.nativeElement as HTMLElement).querySelector<HTMLElement>(
          '[data-testid="confirm-accept"] button',
        );
        (first ?? button)?.focus();
      });
    });
  }

  protected setValue(key: string, value: string): void {
    this.values.update((v) => ({ ...v, [key]: value }));
  }

  protected accept(): void {
    if (!this.valid()) return;
    const values = Object.fromEntries(
      Object.entries(this.values()).map(([k, v]) => [k, (v ?? '').toString().trim()]),
    );
    const first = this.fields()[0]?.key;
    this.service.settle({ confirmed: true, value: first ? values[first] : '', values });
  }

  protected cancel(): void {
    this.service.settle(CANCELLED);
  }
}
