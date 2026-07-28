import { createClient } from "@/lib/supabase/server";

export async function fetchInboxOpenCount(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("inbox_item")
    .select("id", { count: "exact", head: true })
    .eq("status", "open");
  if (error) throw error;
  return count ?? 0;
}
