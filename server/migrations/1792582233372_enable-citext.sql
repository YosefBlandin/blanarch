-- Up Migration
-- Case-insensitive text, used from phase 1 for emails and team names.
create extension if not exists citext;

-- Down Migration
drop extension if exists citext;
