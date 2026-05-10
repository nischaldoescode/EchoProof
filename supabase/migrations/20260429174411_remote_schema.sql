
  create table "public"."echo_replies" (
    "id" uuid not null default gen_random_uuid(),
    "echo_id" uuid not null,
    "parent_reply_id" uuid,
    "user_id" uuid not null,
    "content" text not null,
    "mentioned_users" uuid[] not null default '{}'::uuid[],
    "author_weight" integer not null default 1,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."echo_replies" enable row level security;

alter table "public"."deletion_requests" enable row level security;

alter table "public"."echoes" add column "media_urls" text[] not null default '{}'::text[];

alter table "public"."echoes" add column "reply_count" integer not null default 0;

alter table "public"."users_private" alter column "email" drop not null;

CREATE INDEX echo_replies_echo_id_idx ON public.echo_replies USING btree (echo_id);

CREATE INDEX echo_replies_parent_idx ON public.echo_replies USING btree (parent_reply_id);

CREATE UNIQUE INDEX echo_replies_pkey ON public.echo_replies USING btree (id);

CREATE INDEX echo_replies_user_id_idx ON public.echo_replies USING btree (user_id);

alter table "public"."echo_replies" add constraint "echo_replies_pkey" PRIMARY KEY using index "echo_replies_pkey";

alter table "public"."echo_replies" add constraint "echo_replies_content_check" CHECK (((char_length(content) >= 1) AND (char_length(content) <= 500))) not valid;

alter table "public"."echo_replies" validate constraint "echo_replies_content_check";

alter table "public"."echo_replies" add constraint "echo_replies_echo_id_fkey" FOREIGN KEY (echo_id) REFERENCES public.echoes(id) ON DELETE CASCADE not valid;

alter table "public"."echo_replies" validate constraint "echo_replies_echo_id_fkey";

alter table "public"."echo_replies" add constraint "echo_replies_parent_reply_id_fkey" FOREIGN KEY (parent_reply_id) REFERENCES public.echo_replies(id) ON DELETE CASCADE not valid;

alter table "public"."echo_replies" validate constraint "echo_replies_parent_reply_id_fkey";

alter table "public"."echo_replies" add constraint "echo_replies_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users_public(id) ON DELETE CASCADE not valid;

alter table "public"."echo_replies" validate constraint "echo_replies_user_id_fkey";
set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.increment_reply_count(p_echo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  update echoes set reply_count = reply_count + 1 where id = p_echo_id;
end;
$function$
;

grant delete on table "public"."echo_replies" to "anon";

grant insert on table "public"."echo_replies" to "anon";

grant references on table "public"."echo_replies" to "anon";

grant select on table "public"."echo_replies" to "anon";

grant trigger on table "public"."echo_replies" to "anon";

grant truncate on table "public"."echo_replies" to "anon";

grant update on table "public"."echo_replies" to "anon";

grant delete on table "public"."echo_replies" to "authenticated";

grant insert on table "public"."echo_replies" to "authenticated";

grant references on table "public"."echo_replies" to "authenticated";

grant select on table "public"."echo_replies" to "authenticated";

grant trigger on table "public"."echo_replies" to "authenticated";

grant truncate on table "public"."echo_replies" to "authenticated";

grant update on table "public"."echo_replies" to "authenticated";

grant delete on table "public"."echo_replies" to "service_role";

grant insert on table "public"."echo_replies" to "service_role";

grant references on table "public"."echo_replies" to "service_role";

grant select on table "public"."echo_replies" to "service_role";

grant trigger on table "public"."echo_replies" to "service_role";

grant truncate on table "public"."echo_replies" to "service_role";

grant update on table "public"."echo_replies" to "service_role";


  create policy "authenticated can create reply"
  on "public"."echo_replies"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "authenticated can read replies"
  on "public"."echo_replies"
  as permissive
  for select
  to authenticated
using (true);



  create policy "users can view own echoes"
  on "public"."echoes"
  as permissive
  for select
  to authenticated
using ((auth.uid() = user_id));



  create policy "Service role full access"
  on "public"."users_private"
  as permissive
  for all
  to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));



  create policy "User can read own private data"
  on "public"."users_private"
  as permissive
  for select
  to public
using ((auth.uid() = id));



  create policy "Public read"
  on "public"."users_public"
  as permissive
  for select
  to public
using (true);



