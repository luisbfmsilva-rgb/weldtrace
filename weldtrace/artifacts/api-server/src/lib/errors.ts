// ─────────────────────────────────────────────────────────────────────────────
// WeldTrace — Centralised error handling utilities
// ─────────────────────────────────────────────────────────────────────────────

import { Response } from "express";
import { ZodError } from "zod/v4";
import type { ApiErrorResponse } from "../types/index.js";

// ── Typed API error class ─────────────────────────────────────────────────────

export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly code?: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export class NotFoundError extends ApiError {
  constructor(resource: string) {
    super(404, `${resource} not found`, "NOT_FOUND");
  }
}

export class ValidationError extends ApiError {
  constructor(message: string, details?: unknown) {
    super(400, message, "VALIDATION_ERROR", details);
  }
}

export class ForbiddenError extends ApiError {
  constructor(message = "Access denied") {
    super(403, message, "FORBIDDEN");
  }
}

export class UnauthorizedError extends ApiError {
  constructor(message = "Not authenticated") {
    super(401, message, "UNAUTHORIZED");
  }
}

export class ConflictError extends ApiError {
  constructor(message: string) {
    super(409, message, "CONFLICT");
  }
}

// ── Response helpers ──────────────────────────────────────────────────────────

export function sendError(res: Response, error: unknown): void {
  if (error instanceof ApiError) {
    const body: ApiErrorResponse = { error: error.message, code: error.code };
    if (error.details !== undefined) body.details = error.details;
    res.status(error.statusCode).json(body);
    return;
  }

  if (error instanceof ZodError) {
    res.status(400).json({
      error: "Validation failed",
      code: "VALIDATION_ERROR",
      details: error.issues.map((i) => ({
        path: i.path.join("."),
        message: i.message,
      })),
    });
    return;
  }

  // Supabase / PostgreSQL error codes
  if (typeof error === "object" && error !== null) {
    const e = error as Record<string, unknown>;
    // Unique constraint violation
    if (e["code"] === "23505") {
      res.status(409).json({ error: "Record already exists", code: "CONFLICT" });
      return;
    }
    // Foreign key violation
    if (e["code"] === "23503") {
      res.status(400).json({ error: "Referenced record does not exist", code: "FOREIGN_KEY_ERROR" });
      return;
    }
    if (typeof e["message"] === "string") {
      res.status(500).json({ error: e["message"], code: "INTERNAL_ERROR" });
      return;
    }
  }

  console.error("[ApiError] Unhandled error:", error);
  res.status(500).json({ error: "An unexpected error occurred", code: "INTERNAL_ERROR" });
}

// ── Supabase query result unwrapper ──────────────────────────────────────────

export function unwrap<T>(
  result: { data: T | null; error: { message: string } | null },
  notFoundMessage?: string,
): T {
  if (result.error) {
    const err = result.error as Record<string, unknown>;
    if (err["code"] === "PGRST116" || notFoundMessage) {
      throw new NotFoundError(notFoundMessage ?? "Resource");
    }
    throw new ApiError(500, result.error.message, "DB_ERROR");
  }
  if (result.data === null) {
    throw new NotFoundError(notFoundMessage ?? "Resource");
  }
  return result.data;
}
