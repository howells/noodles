package main

import (
	"context"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/desktop"
	"github.com/howells/noodles/internal/killer"
)

type App struct {
	ctx     context.Context
	service *desktop.Service
}

func NewApp() *App {
	return &App{service: desktop.NewProductionService()}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

func (a *App) Scan(query app.Query) (app.Snapshot, error) {
	return a.service.Scan(a.ctx, query)
}

func (a *App) KillService(request killer.KillRequest) (killer.KillResult, error) {
	return a.service.KillService(a.ctx, request)
}
