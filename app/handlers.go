package main

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
)

// =============================================================
// Query 1: Read — Single Table
// =============================================================

// GET /api/transactions/:id — Point select by PK
func q1GetTransaction(c echo.Context) error {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	var tx TransactionResponse
	err = db.QueryRow(ctx, `
		SELECT id, user_id, corporate_id, amount, currency, tx_type, status, created_at, completed_at
		FROM transaction_record
		WHERE id = $1
	`, id).Scan(
		&tx.ID, &tx.UserID, &tx.CorporateID, &tx.Amount,
		&tx.Currency, &tx.TxType, &tx.Status, &tx.CreatedAt, &tx.CompletedAt,
	)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "transaction not found"})
	}

	return c.JSON(http.StatusOK, tx)
}

// GET /api/transactions/summary/:corporate_id — Range scan with aggregation
func q1TransactionSummary(c echo.Context) error {
	corpID, err := strconv.ParseInt(c.Param("corporate_id"), 10, 64)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid corporate_id"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT 
			status,
			COUNT(*) AS tx_count,
			SUM(amount) AS total_amount,
			AVG(amount) AS avg_amount,
			MIN(created_at) AS earliest,
			MAX(created_at) AS latest
		FROM transaction_record
		WHERE corporate_id = $1
		GROUP BY status
		ORDER BY total_amount DESC
	`, corpID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var results []TransactionSummaryRow
	for rows.Next() {
		var r TransactionSummaryRow
		if err := rows.Scan(&r.Status, &r.TxCount, &r.TotalAmount, &r.AvgAmount, &r.Earliest, &r.Latest); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		results = append(results, r)
	}

	return c.JSON(http.StatusOK, results)
}

// =============================================================
// Query 2: Read — Join 2 Tables (Corporate + User)
// =============================================================

// GET /api/corporates/:id/users
func q2GetCorporateUsers(c echo.Context) error {
	corpID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT 
			c.name AS corporate_name,
			c.industry,
			u.id AS user_id,
			u.full_name,
			u.role,
			u.department,
			u.last_login_at
		FROM corporate c
		INNER JOIN app_user u ON u.corporate_id = c.id
		WHERE c.id = $1
		  AND u.is_active = TRUE
		ORDER BY u.last_login_at DESC NULLS LAST
		LIMIT 50
	`, corpID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var results []CorporateUserRow
	for rows.Next() {
		var r CorporateUserRow
		if err := rows.Scan(&r.CorporateName, &r.Industry, &r.UserID, &r.FullName, &r.Role, &r.Department, &r.LastLoginAt); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		results = append(results, r)
	}

	return c.JSON(http.StatusOK, results)
}

// =============================================================
// Query 3: Read — Join 3 Tables (Corporate + User + Transaction)
// =============================================================

// GET /api/corporates/:id/report
func q3GetCorporateReport(c echo.Context) error {
	corpID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT
			c.name AS corporate_name,
			c.industry,
			u.full_name,
			u.department,
			COUNT(t.id) AS tx_count,
			SUM(t.amount) AS total_amount,
			AVG(t.amount) AS avg_amount,
			MAX(t.created_at) AS last_tx_date
		FROM corporate c
		INNER JOIN app_user u ON u.corporate_id = c.id
		INNER JOIN transaction_record t ON t.user_id = u.id AND t.corporate_id = c.id
		WHERE c.id = $1
		  AND t.status = 'completed'
		GROUP BY c.name, c.industry, u.full_name, u.department
		HAVING COUNT(t.id) > 1
		ORDER BY total_amount DESC
		LIMIT 20
	`, corpID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var results []CorporateReportRow
	for rows.Next() {
		var r CorporateReportRow
		if err := rows.Scan(&r.CorporateName, &r.Industry, &r.FullName, &r.Department, &r.TxCount, &r.TotalAmount, &r.AvgAmount, &r.LastTxDate); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		results = append(results, r)
	}

	return c.JSON(http.StatusOK, results)
}

// =============================================================
// Query 4: Write — Single Table
// =============================================================

// POST /api/transactions
func q4CreateTransaction(c echo.Context) error {
	var req CreateTransactionRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	if req.Currency == "" {
		req.Currency = "THB"
	}
	if req.TxType == "" {
		req.TxType = "payment"
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	refCode := fmt.Sprintf("BENCH%012d", rand.Int63n(999999999999))

	var id int64
	err := db.QueryRow(ctx, `
		INSERT INTO transaction_record 
			(user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
		VALUES ($1, $2, $3, $4, $5, 'pending', 'Benchmark transaction', NOW(), $6)
		RETURNING id
	`, req.UserID, req.CorporateID, req.Amount, req.Currency, req.TxType, refCode).Scan(&id)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}

	return c.JSON(http.StatusCreated, map[string]interface{}{
		"id":     id,
		"status": "pending",
	})
}

// =============================================================
// Query 5: ACID Write — 2 Tables (User + Transaction)
// =============================================================

// POST /api/transactions/with-activity
func q5Acid2Table(c echo.Context) error {
	var req AcidRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	tx, err := db.Begin(ctx)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to begin transaction"})
	}
	defer tx.Rollback(ctx)

	// Step 1: Insert transaction
	refCode := fmt.Sprintf("ACID2%012d", rand.Int63n(999999999999))
	var txID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO transaction_record 
			(user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
		VALUES ($1, $2, $3, 'THB', 'payment', 'completed', 'ACID 2-table benchmark', NOW(), $4)
		RETURNING id
	`, req.UserID, req.CorporateID, req.Amount, refCode).Scan(&txID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "insert failed: " + err.Error()})
	}

	// Step 2: Update user activity
	_, err = tx.Exec(ctx, `
		UPDATE app_user SET last_login_at = NOW() WHERE id = $1
	`, req.UserID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "user update failed: " + err.Error()})
	}

	if err := tx.Commit(ctx); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "commit failed: " + err.Error()})
	}

	return c.JSON(http.StatusCreated, map[string]interface{}{
		"transaction_id": txID,
		"status":         "completed",
		"tables_touched": 2,
	})
}

// =============================================================
// Query 6: ACID Write — 3 Tables (Corporate + User + Transaction)
// =============================================================

// POST /api/transactions/full-process
func q6Acid3Table(c echo.Context) error {
	var req AcidRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	ctx, cancel := context.WithTimeout(c.Request().Context(), 3*time.Second)
	defer cancel()

	tx, err := db.Begin(ctx)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to begin transaction"})
	}
	defer tx.Rollback(ctx)

	// Step 1: Lock corporate row and check credit
	var creditLimit float64
	err = tx.QueryRow(ctx, `
		SELECT credit_limit FROM corporate WHERE id = $1 FOR UPDATE
	`, req.CorporateID).Scan(&creditLimit)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "corporate lookup failed: " + err.Error()})
	}

	// Step 2: Insert transaction
	refCode := fmt.Sprintf("ACID3%012d", rand.Int63n(999999999999))
	var txID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO transaction_record 
			(user_id, corporate_id, amount, currency, tx_type, status, description, created_at, reference_code)
		VALUES ($1, $2, $3, 'THB', 'payment', 'completed', 'ACID 3-table benchmark', NOW(), $4)
		RETURNING id
	`, req.UserID, req.CorporateID, req.Amount, refCode).Scan(&txID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "insert failed: " + err.Error()})
	}

	// Step 3: Update user activity
	_, err = tx.Exec(ctx, `
		UPDATE app_user SET last_login_at = NOW() WHERE id = $1
	`, req.UserID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "user update failed: " + err.Error()})
	}

	// Step 4: Deduct from corporate credit
	_, err = tx.Exec(ctx, `
		UPDATE corporate 
		SET credit_limit = credit_limit - $1, updated_at = NOW()
		WHERE id = $2
	`, req.Amount, req.CorporateID)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "corporate update failed: " + err.Error()})
	}

	if err := tx.Commit(ctx); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "commit failed: " + err.Error()})
	}

	return c.JSON(http.StatusCreated, map[string]interface{}{
		"transaction_id":   txID,
		"status":           "completed",
		"tables_touched":   3,
		"credit_remaining": creditLimit - req.Amount,
	})
}

// =============================================================
// Query 7: Skip Scan (PG 18 feature)
// Tests composite index skip scan optimization
// Index: idx_tx_corp_created ON transaction_record(corporate_id, created_at)
// =============================================================

// GET /api/skip-scan/recent-corporates
// Q7a: Range query on second column without leading column filter
// PG 17: Falls back to idx_tx_created or seq scan
// PG 18: Uses skip scan on composite index
func q7RecentCorporates(c echo.Context) error {
	ctx, cancel := context.WithTimeout(c.Request().Context(), 5*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT
			corporate_id,
			COUNT(*) AS tx_count,
			SUM(amount) AS total_amount
		FROM transaction_record
		WHERE created_at BETWEEN NOW() - INTERVAL '7 days' AND NOW()
		GROUP BY corporate_id
		ORDER BY total_amount DESC
		LIMIT 20
	`)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var results []SkipScanResult
	for rows.Next() {
		var r SkipScanResult
		if err := rows.Scan(&r.CorporateID, &r.TxCount, &r.TotalAmount); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		results = append(results, r)
	}

	return c.JSON(http.StatusOK, results)
}

// GET /api/skip-scan/distinct-corporates
// Q7b: DISTINCT on leading column using skip scan
// PG 18 can skip through the index instead of scanning all rows
func q7DistinctCorporates(c echo.Context) error {
	ctx, cancel := context.WithTimeout(c.Request().Context(), 5*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT DISTINCT corporate_id
		FROM transaction_record
		WHERE created_at >= NOW() - INTERVAL '30 days'
	`)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var corporateIDs []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		corporateIDs = append(corporateIDs, id)
	}

	return c.JSON(http.StatusOK, map[string]interface{}{
		"count":         len(corporateIDs),
		"corporate_ids": corporateIDs,
	})
}

// GET /api/skip-scan/active-corporates
// Q7c: EXISTS pattern - find corporates with recent transactions
// Another pattern that benefits from skip scan
func q7ActiveCorporates(c echo.Context) error {
	ctx, cancel := context.WithTimeout(c.Request().Context(), 5*time.Second)
	defer cancel()

	rows, err := db.Query(ctx, `
		SELECT c.id, c.name
		FROM corporate c
		WHERE EXISTS (
			SELECT 1
			FROM transaction_record t
			WHERE t.corporate_id = c.id
			  AND t.created_at >= NOW() - INTERVAL '7 days'
		)
		ORDER BY c.id
		LIMIT 50
	`)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	defer rows.Close()

	var results []ActiveCorporateResult
	for rows.Next() {
		var r ActiveCorporateResult
		if err := rows.Scan(&r.ID, &r.Name); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		results = append(results, r)
	}

	return c.JSON(http.StatusOK, results)
}
