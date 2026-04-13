-- =============================================================================
-- Roma Segreta — Migration v5
-- New tables: staff_cash, staff_todos, chat_messages
-- Deduplication: UNIQUE on bookings.lodgify_booking_id
-- =============================================================================

-- ============================================================
-- 1. Booking deduplication — add UNIQUE on lodgify_booking_id
-- ============================================================
-- First, remove duplicates keeping the latest row per lodgify_booking_id
DELETE FROM bookings a USING bookings b
WHERE a.lodgify_booking_id = b.lodgify_booking_id
  AND a.lodgify_booking_id IS NOT NULL
  AND a.created_at < b.created_at;

-- Add unique constraint (if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'idx_bookings_lodgify_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_bookings_lodgify_unique ON bookings (lodgify_booking_id) WHERE lodgify_booking_id IS NOT NULL;
  END IF;
END $$;

-- ============================================================
-- 2. staff_cash (tassa di soggiorno tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_cash (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  guest_name text NOT NULL,
  property_id uuid REFERENCES properties(id),
  amount numeric(10,2) NOT NULL,
  collected_by text NOT NULL, -- 'maria' or 'sara'
  collected_at timestamptz DEFAULT now(),
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_cash_date ON staff_cash (collected_at DESC);

-- ============================================================
-- 3. staff_todos (task management with archive)
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_todos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title text NOT NULL,
  assigned_to text, -- 'maria', 'sara', or null for all
  created_by text NOT NULL DEFAULT 'andrea',
  is_completed boolean DEFAULT false,
  completed_at timestamptz,
  is_archived boolean DEFAULT false,
  archived_at timestamptz,
  priority integer DEFAULT 0, -- 0 normal, 1 high
  due_date date,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_todos_active ON staff_todos (is_archived, is_completed, created_at DESC);

-- ============================================================
-- 4. chat_messages (group chat)
-- ============================================================
CREATE TABLE IF NOT EXISTS chat_messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sender text NOT NULL, -- 'andrea', 'maria', 'sara'
  sender_name text NOT NULL, -- display name
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_date ON chat_messages (created_at DESC);

-- ============================================================
-- 5. RLS — Enable on new tables
-- ============================================================
ALTER TABLE staff_cash ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_todos ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Policies for authenticated users
CREATE POLICY "authenticated_all" ON staff_cash FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated_all" ON staff_todos FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated_all" ON chat_messages FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Anon policies (needed for initial load before auth completes)
CREATE POLICY "anon_all" ON staff_cash FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON staff_todos FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all" ON chat_messages FOR ALL TO anon USING (true) WITH CHECK (true);

-- ============================================================
-- 6. Realtime for chat
-- ============================================================
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE staff_todos;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 7. Reload PostgREST schema cache
-- ============================================================
NOTIFY pgrst, 'reload schema';
