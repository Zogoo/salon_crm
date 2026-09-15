import { Pipe, PipeTransform } from '@angular/core';

/**
 * Phone numbers are stored as E.164 ("+17735550581") because that is what
 * search and SMS need; people read them as "(773) 555-0581". US numbers only,
 * which is every client of the four locations; anything else is shown as stored.
 */
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return '';
  const us = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(phone);
  return us ? `(${us[1]}) ${us[2]}-${us[3]}` : phone;
}

@Pipe({ name: 'phone' })
export class PhonePipe implements PipeTransform {
  transform(phone: string | null | undefined): string {
    return formatPhone(phone);
  }
}
