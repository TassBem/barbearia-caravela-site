-- Barbearia Caravela — esquema da base de dados (Supabase / Postgres)
-- Cola este ficheiro inteiro no SQL Editor do Supabase (Database > SQL Editor > New query)
-- e clica em "Run". Podes correr isto mais do que uma vez sem problemas.

create extension if not exists pgcrypto;

-- Clientes (cartão de fidelização): uma linha por número de telemóvel.
-- O 10º corte é sempre grátis (stamps conta 0-9, ver CYCLE_LENGTH no site).
-- "tier" é o nível do cliente: normal -> gold -> premium. Cada vez que um
-- ciclo de 10 se completa o cliente sobe um nível (fica nesse nível para
-- sempre, os ciclos continuam a dar o corte grátis mas o nível não sobe mais
-- depois de premium). Gold acrescenta sobrancelhas grátis em todos os
-- cortes; premium acrescenta ainda 2€ de desconto em todos os serviços.
-- Isto é só o estado guardado; o barbeiro aplica os benefícios ao balcão.
create table if not exists customers (
  phone      text primary key,
  name       text,
  stamps     int not null default 0,
  tier       text not null default 'normal' check (tier in ('normal','gold','premium')),
  created_at timestamptz not null default now()
);
-- Se a tabela já existir de uma versão anterior do site, isto acrescenta a
-- coluna em falta sem tocar nos dados que já lá estão, e remove a antiga
-- coluna "gold" (versão anterior deste cartão) se por acaso já tiver sido
-- criada.
alter table customers add column if not exists tier text not null default 'normal';
alter table customers drop column if exists gold;

-- Histórico de cortes que contam para o cartão de fidelização.
create table if not exists customer_history (
  id         uuid primary key default gen_random_uuid(),
  phone      text not null references customers(phone) on delete cascade,
  date       date not null,
  service    text not null,
  redeemed   boolean not null default false,
  created_at timestamptz not null default now()
);

-- Marcações (passadas, presentes e futuras).
create table if not exists bookings (
  id         text primary key,
  phone      text not null,
  name       text,
  service    text not null,
  barber_id  text,
  date       date not null,
  time       text not null,
  status     text not null default 'agendado', -- agendado | concluido | cancelado
  redeemed   boolean not null default false,
  created_at timestamptz not null default now()
);

-- PINs de acesso (clientes e barbeiros), guardados sempre como hash, nunca em texto.
create table if not exists pins (
  phone      text primary key,
  pin_hash   text not null,
  created_at timestamptz not null default now()
);

-- Folgas/férias: dias em que um barbeiro não está disponível para marcações.
create table if not exists time_off (
  id         uuid primary key default gen_random_uuid(),
  barber_id  text not null,
  date       date not null,
  created_at timestamptz not null default now(),
  unique (barber_id, date)
);

-- Segurança ao nível das linhas (RLS). Modelo simples escolhido para já:
-- qualquer pessoa com a "publishable key" do site consegue ler e escrever.
-- Adequado para uma barbearia pequena sem dados de pagamento. Pode ser
-- reforçado mais tarde com Supabase Edge Functions, se um dia for preciso.
alter table customers enable row level security;
alter table customer_history enable row level security;
alter table bookings enable row level security;
alter table pins enable row level security;
alter table time_off enable row level security;

drop policy if exists "public read customers" on customers;
drop policy if exists "public write customers" on customers;
drop policy if exists "public update customers" on customers;
create policy "public read customers" on customers for select using (true);
create policy "public write customers" on customers for insert with check (true);
create policy "public update customers" on customers for update using (true);

drop policy if exists "public read history" on customer_history;
drop policy if exists "public write history" on customer_history;
create policy "public read history" on customer_history for select using (true);
create policy "public write history" on customer_history for insert with check (true);

drop policy if exists "public read bookings" on bookings;
drop policy if exists "public write bookings" on bookings;
drop policy if exists "public update bookings" on bookings;
create policy "public read bookings" on bookings for select using (true);
create policy "public write bookings" on bookings for insert with check (true);
create policy "public update bookings" on bookings for update using (true);

drop policy if exists "public read pins" on pins;
drop policy if exists "public write pins" on pins;
drop policy if exists "public update pins" on pins;
create policy "public read pins" on pins for select using (true);
create policy "public write pins" on pins for insert with check (true);
create policy "public update pins" on pins for update using (true);

drop policy if exists "public read time_off" on time_off;
drop policy if exists "public write time_off" on time_off;
drop policy if exists "public delete time_off" on time_off;
create policy "public read time_off" on time_off for select using (true);
create policy "public write time_off" on time_off for insert with check (true);
create policy "public delete time_off" on time_off for delete using (true);

-- ================= Conta de teste (999999999 / PIN 0000) =================
-- Cartão de fidelização com 3 carimbos já feitos.
insert into customers (phone, name, stamps) values ('999999999', 'Conta de Teste', 3)
  on conflict (phone) do update set stamps = excluded.stamps, name = excluded.name;

insert into customer_history (phone, date, service, redeemed)
  select '999999999', '2025-11-07', 'corte', false
  where not exists (select 1 from customer_history where phone = '999999999' and date = '2025-11-07');
insert into customer_history (phone, date, service, redeemed)
  select '999999999', '2025-12-12', 'corte', false
  where not exists (select 1 from customer_history where phone = '999999999' and date = '2025-12-12');
insert into customer_history (phone, date, service, redeemed)
  select '999999999', '2026-01-01', 'corte', false
  where not exists (select 1 from customer_history where phone = '999999999' and date = '2026-01-01');

-- Uma marcação passada (concluída) e uma futura (agendada).
insert into bookings (id, phone, name, service, barber_id, date, time, status) values
  ('bk_demo_past',   '999999999', 'Conta de Teste', 'corte', 'demo', '2026-01-01', '10:00', 'concluido')
  on conflict (id) do nothing;
insert into bookings (id, phone, name, service, barber_id, date, time, status) values
  ('bk_demo_future', '999999999', 'Conta de Teste', 'corte', 'demo', '2026-12-31', '10:00', 'agendado')
  on conflict (id) do nothing;

-- PIN da conta de teste: 0000 (SHA-256 de "caravela:999999999:0000")
insert into pins (phone, pin_hash) values
  ('999999999', '19416e53ab9e518d856000fddec7627665515d79029e84b4ca45b8a82c705457')
  on conflict (phone) do update set pin_hash = excluded.pin_hash;
