-- Enable pgvector only; application tables and RLS are Ch.5 coursework.
\connect postgres
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
