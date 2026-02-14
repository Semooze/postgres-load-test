package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

var db *pgxpool.Pool

func main() {
	// Database connection
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		// Default: direct connection
		// With PgBouncer: postgresql://postgres:password@127.0.0.1:6432/benchdb
		dsn = "postgresql://postgres:password@localhost:5432/benchdb?sslmode=disable"
	}

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatalf("Failed to parse DSN: %v", err)
	}

	// Connection pool settings
	poolConfig.MaxConns = 100
	poolConfig.MinConns = 10
	poolConfig.MaxConnLifetime = 30 * time.Minute
	poolConfig.MaxConnIdleTime = 5 * time.Minute
	poolConfig.HealthCheckPeriod = 30 * time.Second

	db, err = pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Verify connection
	if err := db.Ping(context.Background()); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}
	log.Println("Connected to database")

	// Echo setup
	e := echo.New()
	e.HideBanner = true

	// Middleware
	e.Use(middleware.Recover())

	// Health check
	e.GET("/health", healthCheck)

	// Query 1: Read single table
	e.GET("/api/transactions/:id", q1GetTransaction)
	e.GET("/api/transactions/summary/:corporate_id", q1TransactionSummary)

	// Query 2: Read 2-table join
	e.GET("/api/corporates/:id/users", q2GetCorporateUsers)

	// Query 3: Read 3-table join
	e.GET("/api/corporates/:id/report", q3GetCorporateReport)

	// Query 4: Write single table
	e.POST("/api/transactions", q4CreateTransaction)

	// Query 5: ACID 2-table write
	e.POST("/api/transactions/with-activity", q5Acid2Table)

	// Query 6: ACID 3-table write
	e.POST("/api/transactions/full-process", q6Acid3Table)

	// Query 7: Skip scan (PG 18 feature)
	e.GET("/api/skip-scan/recent-corporates", q7RecentCorporates)
	e.GET("/api/skip-scan/distinct-corporates", q7DistinctCorporates)
	e.GET("/api/skip-scan/active-corporates", q7ActiveCorporates)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting server on :%s", port)
	if err := e.Start(":" + port); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func healthCheck(c echo.Context) error {
	ctx, cancel := context.WithTimeout(c.Request().Context(), 2*time.Second)
	defer cancel()

	if err := db.Ping(ctx); err != nil {
		return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "unhealthy", "error": err.Error()})
	}

	stats := db.Stat()
	return c.JSON(http.StatusOK, map[string]interface{}{
		"status":           "healthy",
		"total_conns":      stats.TotalConns(),
		"idle_conns":       stats.IdleConns(),
		"acquired_conns":   stats.AcquiredConns(),
		"max_conns":        stats.MaxConns(),
	})
}

// =============================================================
// Response types
// =============================================================

type TransactionResponse struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	CorporateID int64     `json:"corporate_id"`
	Amount      float64    `json:"amount"`
	Currency    string     `json:"currency"`
	TxType      string     `json:"tx_type"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

type TransactionSummaryRow struct {
	Status      string  `json:"status"`
	TxCount     int64   `json:"tx_count"`
	TotalAmount float64 `json:"total_amount"`
	AvgAmount   float64 `json:"avg_amount"`
	Earliest    time.Time `json:"earliest"`
	Latest      time.Time `json:"latest"`
}

type CorporateUserRow struct {
	CorporateName string     `json:"corporate_name"`
	Industry      string     `json:"industry"`
	UserID        int64      `json:"user_id"`
	FullName      string     `json:"full_name"`
	Role          string     `json:"role"`
	Department    string     `json:"department"`
	LastLoginAt   *time.Time `json:"last_login_at,omitempty"`
}

type CorporateReportRow struct {
	CorporateName string  `json:"corporate_name"`
	Industry      string  `json:"industry"`
	FullName      string  `json:"full_name"`
	Department    string  `json:"department"`
	TxCount       int64   `json:"tx_count"`
	TotalAmount   float64 `json:"total_amount"`
	AvgAmount     float64 `json:"avg_amount"`
	LastTxDate    time.Time `json:"last_tx_date"`
}

type CreateTransactionRequest struct {
	UserID      int64   `json:"user_id"`
	CorporateID int64  `json:"corporate_id"`
	Amount      float64 `json:"amount"`
	Currency    string  `json:"currency"`
	TxType      string  `json:"tx_type"`
}

type AcidRequest struct {
	UserID      int64   `json:"user_id"`
	CorporateID int64   `json:"corporate_id"`
	Amount      float64 `json:"amount"`
}

// Q7 Skip Scan response types
type SkipScanResult struct {
	CorporateID int64   `json:"corporate_id"`
	TxCount     int64   `json:"tx_count"`
	TotalAmount float64 `json:"total_amount"`
}

type ActiveCorporateResult struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
