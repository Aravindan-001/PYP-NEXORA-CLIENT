import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-razorpay-signature",
};

async function verifyHmacSha256(secret: string, rawBody: string, expectedHex: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const msgData = encoder.encode(rawBody);

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
    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
    if (!webhookSecret) {
      return new Response(JSON.stringify({ error: "Webhook secret not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const signatureHeader = req.headers.get("x-razorpay-signature") || req.headers.get("X-Razorpay-Signature");
    if (!signatureHeader) {
      return new Response(JSON.stringify({ error: "Missing Razorpay webhook signature header" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rawBody = await req.text();
    const isValidSignature = await verifyHmacSha256(webhookSecret, rawBody, signatureHeader);

    if (!isValidSignature) {
      return new Response(JSON.stringify({ error: "Invalid webhook signature" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = JSON.parse(rawBody);
    const eventType = payload.event;
    const paymentEntity = payload.payload?.payment?.entity;
    const refundEntity = payload.payload?.refund?.entity;

    // Stable deterministic event ID resolution
    // Official Razorpay webhooks pass event_id or id.
    // If missing, construct a deterministic key using eventType, entity id, and created_at.
    let eventId = payload.event_id || payload.id;
    if (!eventId) {
      const entityId = paymentEntity?.id || refundEntity?.id || paymentEntity?.order_id;
      const createdAt = payload.created_at;
      if (entityId && createdAt) {
        eventId = `${eventType}_${entityId}_${createdAt}`;
      }
    }

    if (!eventId) {
      return new Response(
        JSON.stringify({ error: "Missing stable event identifier in webhook payload" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "http://127.0.0.1:54321";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseServiceKey) {
      return new Response(JSON.stringify({ error: "Server configuration missing" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminSupabase = createClient(supabaseUrl, supabaseServiceKey);

    // Check if event was already processed
    const { data: existingEvent } = await adminSupabase
      .from("processed_webhook_events")
      .select("event_id")
      .eq("event_id", eventId)
      .maybeSingle();

    if (existingEvent) {
      return new Response(
        JSON.stringify({ status: "already_processed", event_id: eventId }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Process event based on type
    if (eventType === "payment.captured") {
      if (!paymentEntity) {
        return new Response(JSON.stringify({ error: "Invalid payment payload" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      let bookingId = paymentEntity.notes?.booking_id;
      if (!bookingId) {
        const { data: dbPayment } = await adminSupabase
          .from("payments")
          .select("booking_id")
          .eq("provider_order_id", paymentEntity.order_id)
          .maybeSingle();

        bookingId = dbPayment?.booking_id;
      }

      if (!bookingId) {
        return new Response(JSON.stringify({ error: "Booking not found for order" }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { error: rpcError } = await adminSupabase.rpc(
        "process_payment_success",
        {
          p_booking_id: bookingId,
          p_provider_order_id: paymentEntity.order_id,
          p_provider_payment_id: paymentEntity.id,
          p_amount_paise: paymentEntity.amount,
        },
        { schema: "private" }
      );

      if (rpcError) {
        return new Response(
          JSON.stringify({ error: "Failed to process payment in database: " + rpcError.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } else if (eventType === "payment.failed") {
      if (paymentEntity?.order_id) {
        const { error: updateError } = await adminSupabase
          .from("payments")
          .update({ status: "failed" })
          .eq("provider_order_id", paymentEntity.order_id);

        if (updateError) {
          return new Response(
            JSON.stringify({ error: "Failed to update failed payment status: " + updateError.message }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    } else if (eventType === "refund.processed" || eventType === "refund.created" || eventType === "payment.refunded") {
      const providerPaymentId = refundEntity?.payment_id || paymentEntity?.id;
      const refundAmount = refundEntity?.amount || paymentEntity?.amount_refunded;

      if (providerPaymentId && refundAmount != null) {
        const { error: refundError } = await adminSupabase.rpc(
          "process_refund_success",
          {
            p_provider_payment_id: providerPaymentId,
            p_refund_amount_paise: refundAmount,
          },
          { schema: "private" }
        );

        if (refundError) {
          return new Response(
            JSON.stringify({ error: "Failed to process refund in database: " + refundError.message }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    }

    // Record processed event in DB. Handle duplicate key 23505 gracefully for concurrent deliveries.
    const { error: insertEventError } = await adminSupabase
      .from("processed_webhook_events")
      .insert({
        event_id: eventId,
        event_type: eventType,
      });

    if (insertEventError) {
      if (insertEventError.code === "23505" || insertEventError.message?.includes("duplicate key")) {
        return new Response(
          JSON.stringify({ status: "already_processed", event_id: eventId }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      // If unable to record event ID due to other DB failure, return 500 so Razorpay retries
      return new Response(
        JSON.stringify({ error: "Failed to record webhook event: " + insertEventError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ status: "success", event_id: eventId }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
