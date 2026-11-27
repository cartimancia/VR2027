// Supabase connection used by index.html (guest RSVP) and admin.html.
// Values: Supabase dashboard > Project Settings > API.
//
// The anon / publishable key is designed to be public: access is controlled
// by the RLS policies and functions in supabase/schema.sql.
// NEVER put the service_role / secret key here: this file is public.
window.SUPABASE = {
  url: "",      // e.g. "https://abcdefgh.supabase.co"
  anonKey: ""   // anon (legacy) or publishable key
};
