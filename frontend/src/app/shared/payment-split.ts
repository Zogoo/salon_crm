import { Component, computed, effect, input, output, signal, untracked } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { PaymentPart, TenderMethod } from '../core/models';
import { UiIcon } from '../ui';

interface Row {
  method: TenderMethod;
  dollars: number | null;
  code: string;
}

export const TENDER_LABELS: Record<TenderMethod, string> = {
  card: 'Card',
  cash: 'Cash',
  zelle: 'Zelle',
  venmo: 'Venmo',
  gift_card: 'Gift card',
  online: 'Online',
  other: 'Other',
};

/**
 * How the client pays what is due: one method, or split across two
 * (Addendum §1) — for example $70 on a gift card and the rest in cash.
 *
 * The second amount fills itself in with what is left, and a running line
 * says whether the parts add up, so the desk never has to do the sum or guess
 * why the button will not go. The parent reads `parts` and `valid`.
 */
@Component({
  selector: 'app-payment-split',
  imports: [FormsModule, DecimalPipe, UiIcon],
  template: `
    <div class="split__mode" role="radiogroup" aria-label="How is it paid?">
      <button
        type="button"
        role="radio"
        [attr.aria-checked]="!split()"
        (click)="setSplit(false)"
        data-testid="pay-one"
      >
        One method
      </button>
      <button
        type="button"
        role="radio"
        [attr.aria-checked]="split()"
        (click)="setSplit(true)"
        data-testid="pay-split"
      >
        Split between two
      </button>
    </div>

    @for (row of rows(); track $index; let i = $index) {
      <div class="split__row" [attr.data-testid]="'pay-part-' + i">
        <label class="split__field">
          <span>{{ split() ? 'Method ' + (i + 1) : 'Method' }}</span>
          <select
            [ngModel]="row.method"
            (ngModelChange)="update(i, { method: $event })"
            [attr.data-testid]="'pay-method-' + i"
          >
            @for (m of methods; track m) {
              <option [value]="m">{{ labels[m] }}</option>
            }
          </select>
        </label>
        @if (row.method === 'gift_card') {
          <label class="split__field">
            <span>Card code</span>
            <input
              [ngModel]="row.code"
              (ngModelChange)="update(i, { code: $event })"
              placeholder="Scan or type"
              [attr.data-testid]="'pay-code-' + i"
            />
          </label>
        }
        <label class="split__field split__field--amount">
          <span>Amount</span>
          @if (split()) {
            <input
              type="number"
              min="0"
              step="0.01"
              inputmode="decimal"
              [ngModel]="row.dollars"
              (ngModelChange)="update(i, { dollars: $event })"
              [attr.data-testid]="'pay-amount-' + i"
            />
          } @else {
            <output class="split__fixed" [attr.data-testid]="'pay-amount-' + i"
              >\${{ dueCents() / 100 | number: '1.2-2' }}</output
            >
          }
        </label>
      </div>
    }

    @if (split()) {
      <p
        class="split__check"
        [class.split__check--ok]="valid()"
        role="status"
        data-testid="pay-split-check"
      >
        <ui-icon [name]="valid() ? 'check_circle' : 'info'" />
        @if (valid()) {
          Adds up to \${{ dueCents() / 100 | number: '1.2-2' }}.
        } @else if (remainingCents() > 0) {
          \${{ remainingCents() / 100 | number: '1.2-2' }} still to assign of \${{
            dueCents() / 100 | number: '1.2-2'
          }}.
        } @else {
          \${{ -remainingCents() / 100 | number: '1.2-2' }} more than the \${{
            dueCents() / 100 | number: '1.2-2'
          }}
          due — lower one of the amounts.
        }
      </p>
    }
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: flex;
      flex-direction: column;
      gap: var(--sp-3);
    }

    .split__mode {
      display: inline-flex;
      align-self: flex-start;
      gap: var(--sp-1);
      padding: var(--sp-1);
      border: 1px solid var(--md-outline-variant);
      border-radius: 999px;
      background: var(--md-surface-container-high);

      button {
        min-height: 2.5rem;
        padding: 0 var(--sp-4);
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: var(--md-on-surface-variant);
        cursor: pointer;
        font: inherit;
        font-weight: 600;
        @include focus-ring;
      }
      button[aria-checked='true'] {
        background: var(--md-surface);
        color: var(--md-on-surface);
        box-shadow: 0 1px 3px rgb(0 0 0 / 16%);
      }
    }

    .split__row {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(min(9rem, 100%), 1fr));
      gap: var(--sp-2);
      align-items: end;
    }

    .split__field {
      display: flex;
      flex-direction: column;
      gap: var(--sp-1);
      @include type-label-md;
      color: var(--md-on-surface-variant);

      select,
      input,
      output {
        min-height: 2.75rem;
        padding: 0 var(--sp-3);
        border: 1px solid var(--md-outline);
        border-radius: var(--md-shape-sm);
        background: var(--md-surface);
        color: var(--md-on-surface);
        font: inherit;
        @include type-body-lg;
      }
    }

    .split__fixed {
      display: flex;
      align-items: center;
      border-color: transparent !important;
      background: var(--md-surface-container-low) !important;
      font-variant-numeric: tabular-nums;
      font-weight: 600;
    }

    .split__check {
      display: flex;
      align-items: center;
      gap: var(--sp-2);
      padding: var(--sp-2) var(--sp-3);
      border-radius: var(--md-shape-sm);
      background: var(--md-surface-container-low);
      @include type-body-md;
    }
    .split__check--ok {
      background: var(--md-success-container);
      color: var(--md-on-success-container);
    }
  `,
})
export class PaymentSplit {
  /** What the parts must add up to, in cents. */
  readonly dueCents = input.required<number>();
  /** Offer gift cards (checkout does; a deposit, taken before the visit, does not). */
  readonly allowGiftCard = input(true);
  /** Start from what was paid before, when correcting a visit. */
  readonly initial = input<PaymentPart[] | null>(null);
  readonly changed = output<{ parts: PaymentPart[]; valid: boolean }>();

  protected readonly labels = TENDER_LABELS;
  protected readonly split = signal(false);
  protected readonly rows = signal<Row[]>([{ method: 'card', dollars: null, code: '' }]);
  /** Set once the second amount is typed by hand, so it is no longer auto-filled. */
  private secondTouched = false;

  protected get methods(): TenderMethod[] {
    const all: TenderMethod[] = ['card', 'cash', 'zelle', 'venmo', 'gift_card', 'online', 'other'];
    return this.allowGiftCard() ? all : all.filter((m) => m !== 'gift_card');
  }

  readonly parts = computed<PaymentPart[]>(() => {
    const due = this.dueCents();
    if (!this.split()) {
      const row = this.rows()[0];
      return due > 0 ? [this.part(row, due)] : [];
    }
    return this.rows()
      .map((row) => this.part(row, Math.round((row.dollars ?? 0) * 100)))
      .filter((p) => p.amount_cents > 0);
  });

  protected readonly remainingCents = computed(
    () => this.dueCents() - this.parts().reduce((sum, p) => sum + p.amount_cents, 0),
  );

  readonly valid = computed(() => {
    const parts = this.parts();
    if (this.remainingCents() !== 0) return false;
    if (this.split() && parts.length < 2) return false;
    return parts.every((p) => p.method !== 'gift_card' || !!p.code?.trim());
  });

  constructor() {
    effect(() => {
      const start = this.initial();
      if (!start?.length) return;
      untracked(() => {
        this.split.set(start.length > 1);
        this.secondTouched = true;
        this.rows.set(
          start.map((p) => ({
            method: p.method,
            dollars: p.amount_cents / 100,
            code: p.code ?? '',
          })),
        );
      });
    });
    effect(() => this.changed.emit({ parts: this.parts(), valid: this.valid() }));
  }

  protected setSplit(on: boolean): void {
    this.split.set(on);
    const first = this.rows()[0];
    if (on) {
      const half = Math.floor(this.dueCents() / 2) / 100;
      this.secondTouched = false;
      this.rows.set([
        { ...first, dollars: first.dollars ?? half },
        {
          method: first.method === 'cash' ? 'card' : 'cash',
          dollars: null,
          code: '',
        },
      ]);
      this.fillSecond();
    } else {
      this.rows.set([first]);
    }
  }

  protected update(index: number, change: Partial<Row>): void {
    this.rows.update((rows) => rows.map((r, i) => (i === index ? { ...r, ...change } : r)));
    if (index === 1 && change.dollars !== undefined) this.secondTouched = true;
    if (index === 0 && change.dollars !== undefined) this.fillSecond();
  }

  /** The second amount is whatever the first leaves, until the desk types its own. */
  private fillSecond(): void {
    if (!this.split() || this.secondTouched) return;
    const first = Math.round((this.rows()[0].dollars ?? 0) * 100);
    const rest = Math.max(this.dueCents() - first, 0) / 100;
    this.rows.update((rows) => rows.map((r, i) => (i === 1 ? { ...r, dollars: rest } : r)));
  }

  private part(row: Row, cents: number): PaymentPart {
    return row.method === 'gift_card'
      ? { method: row.method, amount_cents: cents, code: row.code.trim() }
      : { method: row.method, amount_cents: cents };
  }
}
