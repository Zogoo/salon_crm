// Development: Angular dev server on :4200 talks cross-origin to the Rails API.
export const environment = {
  production: false,
  apiUrl: 'http://localhost:3011/api/v1',
  defaultLocale: 'en',
  availableLocales: ['en'],
};
