export interface User {
  id: number;
  email: string;
  name: string;
  avatar_url: string | null;
}

export interface Note {
  id: number;
  title: string;
  body: string | null;
  created_at: string;
  updated_at: string;
}

export interface PageMeta {
  count: number;
  page: number;
  pages: number;
  limit: number;
}

export interface NotesPage {
  notes: Note[];
  meta: PageMeta;
}

export interface AuthResponse {
  token: string;
  user: User;
}
