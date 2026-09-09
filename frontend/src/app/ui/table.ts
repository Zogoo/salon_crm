import { Component, input } from '@angular/core';

/**
 * Styling and overflow for a projected `<table>`.
 *
 * Deliberately not a data-table that takes columns and rows: the screens here
 * render genuinely different cells (money, chips, buttons), and a config-driven
 * table would grow a flag per screen. This owns the one thing they all share —
 * how a table looks and how it behaves when it is wider than the phone.
 *
 * On a narrow screen the table scrolls inside this container rather than the
 * page, so the surrounding layout never shifts sideways.
 */
@Component({
  selector: 'ui-table',
  template: `
    <div class="scroll" [attr.role]="'region'" [attr.aria-label]="label()" tabindex="0">
      <ng-content />
    </div>
  `,
  styleUrl: './table.scss',
})
export class UiTable {
  readonly label = input('Data table');
}
