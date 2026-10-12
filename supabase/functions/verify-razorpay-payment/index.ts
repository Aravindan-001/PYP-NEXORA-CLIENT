import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function verifyHmacSha256(secret: string, data: string, expectedHex: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const msgData = encoder.encode(data);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  const hashArray = Array.from(new Uint8Array(signature));
  const calculatedHex = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");

  return calculatedHex === expectedHex;
}

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

    const { booking_id, razorpay_order_id, razorpay_payment_id, razorpay_signature } = await req.json();

    if (!booking_id || !razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      return new Response(JSON.stringify({ error: "Missing required payment verification fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");

    if (!razorpayKeySecret || !razorpayKeyId) {
      return new Response(JSON.stringify({ error: "Razorpay credentials missing" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const bodyToSign = `${razorpay_order_id}|${razorpay_payment_id}`;
    const isValidSignature = await verifyHmacSha256(razorpayKeySecret, bodyToSign, razorpay_signature);

    if (!isValidSignature) {
      return new Response(JSON.stringify({ error: "Invalid Razorpay payment signature" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminSupabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: booking, error: bookingError } = await adminSupabase
      .from("bookings")
      .select("*")
      .eq("id", booking_id)
      .single();

    if (bookingError || !booking) {
      return new Response(JSON.stringify({ error: "Booking not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (booking.customer_id !== user.id) {
      return new Response(JSON.stringify({ error: "Forbidden: User is not booking customer" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authString = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
    const rzpFetch = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: { "Authorization": `Basic ${authString}` },
    });

    if (!rzpFetch.ok) {
      return new Response(JSON.stringify({ error: "Failed to verify payment with Razorpay server" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rzpPayment = await rzpFetch.json();

    if (rzpPayment.order_id !== razorpay_order_id) {
      return new Response(JSON.stringify({ error: "Order ID mismatch in payment details" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (rzpPayment.amount !== booking.total_amount_paise) {
      return new Response(JSON.stringify({ error: "Payment amount mismatch" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (rzpPayment.currency !== "INR") {
      return new Response(JSON.stringify({ error: "Currency mismatch" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (rzpPayment.status !== "captured") {
      return new Response(
        JSON.stringify({
          error: `Payment is in '${rzpPayment.status}' state and not yet captured. Booking cannot be confirmed until capture completes.`,
          captured: false,
          status: rzpPayment.status,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { error: rpcError } = await adminSupabase.rpc("process_payment_success", {
      p_booking_id: booking_id,
      p_provider_order_id: razorpay_order_id,
      p_provider_payment_id: razorpay_payment_id,
      p_amount_paise: booking.total_amount_paise,
    }, { schema: "private" });

    if (rpcError) {
      return new Response(JSON.stringify({ error: "Failed to record payment in database: " + rpcError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        booking_id: booking_id,
        status: "confirmed",
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
