-- =============================================================================
-- Roma Segreta — Fix sync-lodgify
-- Convert partial unique index to proper UNIQUE CONSTRAINT
-- =============================================================================

-- 1. First, remove any existing NULL lodgify_booking_id duplicates
-- (shouldn't be an issue since we're adding a constraint that allows NULLs)

-- 2. Drop the partial unique index
DROP INDEX IF EXISTS idx_bookings_lodgify_unique;

-- 3. Remove any remaining duplicates on lodgify_booking_id (keep latest)
DELETE FROM bookings a USING bookings b
WHERE a.lodgify_booking_id = b.lodgify_booking_id
  AND a.lodgify_booking_id IS NOT NULL
  AND a.created_at < b.created_at;

-- 4. Add a proper UNIQUE CONSTRAINT (not index) on lodgify_booking_id
-- This allows ON CONFLICT (lodgify_booking_id) to work with upsert
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_lodgify_booking_id_key;
ALTER TABLE bookings ADD CONSTRAINT bookings_lodgify_booking_id_key UNIQUE (lodgify_booking_id);

-- 5. Verify
SELECT conname, contype FROM pg_constraint 
WHERE conrelid = 'bookings'::regclass AND conname = 'bookings_lodgify_booking_id_key';

-- 6. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
