import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "http://127.0.0.1:54321";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseServiceKey) {
      return new Response(JSON.stringify({ error: "Server configuration missing" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const clientSupabase = createClient(supabaseUrl, supabaseAnonKey || "", {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await clientSupabase.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { booking_id } = await req.json();
    if (!booking_id) {
      return new Response(JSON.stringify({ error: "Booking ID is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

    if (!razorpayKeyId || !razorpayKeySecret) {
      return new Response(JSON.stringify({ error: "Razorpay credentials not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Call prepare_booking_for_payment RPC which locks the booking row FOR UPDATE,
    // verifies customer authorization, updates status to 'awaiting_payment',
    // and checks for an existing valid pending order.
    const { data: prepData, error: prepError } = await clientSupabase.rpc(
      "prepare_booking_for_payment",
      { p_booking_id: booking_id }
    );

    if (prepError) {
      return new Response(
        JSON.stringify({ error: "Failed to prepare booking for payment: " + prepError.message }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const prepResult = Array.isArray(prepData) ? prepData[0] : prepData;

    if (!prepResult) {
      return new Response(JSON.stringify({ error: "Booking not found or ineligible" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const totalAmountPaise = prepResult.out_total_amount_paise;
    const existingOrderId = prepResult.out_existing_provider_order_id;

    // Reuse existing valid pending order if present
    if (existingOrderId) {
      return new Response(
        JSON.stringify({
          order_id: existingOrderId,
          amount_paise: totalAmountPaise,
          currency: "INR",
          key_id: razorpayKeyId,
          reused: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call Razorpay API to create new order
    const authString = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
    const rzpResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${authString}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: totalAmountPaise,
        currency: "INR",
        receipt: booking_id,
        notes: { booking_id: booking_id },
      }),
    });

    if (!rzpResponse.ok) {
      const rzpErrText = await rzpResponse.text();
      return new Response(
        JSON.stringify({ error: "Razorpay order creation failed", details: rzpErrText }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const rzpOrder = await rzpResponse.json();
    const adminSupabase = createClient(supabaseUrl, supabaseServiceKey);

    // Insert pending payment into DB. Protected by partial unique index payments_pending_booking_idx.
    const { error: insertError } = await adminSupabase.from("payments").insert({
      booking_id: booking_id,
      provider: "razorpay",
      provider_order_id: rzpOrder.id,
      amount_paise: totalAmountPaise,
      status: "pending",
    });

    if (insertError) {
      // Handle Postgres error 23505 (unique constraint violation if a concurrent request inserted first)
      if (insertError.code === "23505" || insertError.message?.includes("payments_pending_booking_idx")) {
        const { data: concurrentPayment } = await adminSupabase
          .from("payments")
          .select("provider_order_id, amount_paise")
          .eq("booking_id", booking_id)
          .eq("status", "pending")
          .maybeSingle();

        if (concurrentPayment?.provider_order_id) {
          return new Response(
            JSON.stringify({
              order_id: concurrentPayment.provider_order_id,
              amount_paise: concurrentPayment.amount_paise,
              currency: "INR",
              key_id: razorpayKeyId,
              reused: true,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      return new Response(
        JSON.stringify({ error: "Failed to record payment order: " + insertError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        order_id: rzpOrder.id,
        amount_paise: totalAmountPaise,
        currency: "INR",
        key_id: razorpayKeyId,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
