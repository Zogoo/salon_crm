// Production: Rails serves the built app from public/, so the API is same-origin.
export const environment = {
  production: true,
  apiUrl: '/api/v1',
  defaultLocale: 'en',
  availableLocales: ['en'],
};
