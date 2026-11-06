const std = @import("std");
const rl = @import("raylib");
const Io = std.Io;

const zig_zag_zoe = @import("zig_zag_zoe");

const assert = std.debug.assert;

const screen_width: u16 = 900;
const screen_height: u16 = 900;

const grid_size: i32 = 3;
const cell_size: i32 = @divExact(screen_width, grid_size);
const grid_border_thickness_px = 10;

pub const board_size: u8 = 3;

pub const Turn = enum { x, o };
pub const Board = [board_size][board_size]?Turn;

const Status = enum { started, x_won, o_won, tie };

const log = std.log;

const Screen = enum { welcome, game, ending };
var active_screen: Screen = .welcome;

var font: rl.Font = undefined;
const font_size_px = 50;
const font_spacing_px = 0;

const color = rl.Color.light_gray;

comptime {
    assert(grid_border_thickness_px % 2 == 0);
    assert(screen_width % 3 == 0);
    assert(screen_height % 3 == 0);
}

const Game = struct {
    board: Board,
    turn: Turn,
    status: Status,
};

var game: Game = undefined;

fn init_game() void {
    game = Game{
        .board = .{.{null} ** 3} ** 3,
        .turn = .x,
        .status = .started,
    };
}
fn next_turn() void {
    game.turn = switch (game.turn) {
        .x => .o,
        .o => .x,
    };
}
fn find_line_winner(first: ?Turn, second: ?Turn, third: ?Turn) ?Turn {
    if (first == second and second == third) return first;
    return null;
}

fn find_winner() ?Turn {
    for (0..board_size) |index| {
        if (find_line_winner(game.board[index][0], game.board[index][1], game.board[index][2])) |turn| return turn;
        if (find_line_winner(game.board[0][index], game.board[1][index], game.board[2][index])) |turn| return turn;
    }
    if (find_line_winner(game.board[0][0], game.board[1][1], game.board[2][2])) |turn| return turn;
    if (find_line_winner(game.board[0][2], game.board[1][1], game.board[2][0])) |turn| return turn;

    return null;
}

fn is_board_full() bool {
    for (game.board) |row| {
        for (row) |cell| {
            if (cell == null) return false;
        }
    }
    return true;
}

fn update_status() void {
    if (find_winner()) |turn| {
        game.status = switch (turn) {
            .x => .x_won,
            .o => .o_won,
        };
        active_screen = .ending;
    }

    if (is_board_full()) {
        game.status = .tie;
        active_screen = .ending;
    }
    log.debug("game status updated: {}", .{game.status});
}

pub fn take_position(x: u8, y: u8) error{PositionOccupied}!void {
    assert(x < board_size);
    assert(y < board_size);

    const cell = &game.board[x][y];
    if (cell.* != null) {
        log.debug("position ({}, {}) already occupied", .{ x, y });
        return error.PositionOccupied;
    }

    const turn = game.turn;
    cell.* = turn;
    log.debug("position ({}, {}) taken by {}", .{ x, y, turn });

    update_status();
    next_turn();
    assert(game.turn != turn);
}

fn init_window() error{LoadFont}!void {
    rl.initWindow(screen_width, screen_height, "Zig Zag Zoe");

    font = try rl.getFontDefault();

    rl.setTargetFPS(60);
}

fn deinit_window() void {
    rl.closeWindow();
    rl.unloadFont(font);
}
fn text_from_mark(mark: Turn) [:0]const u8 {
    return switch (mark) {
        .x => "x",
        .o => "o",
    };
}

fn draw_centered_text(text: [:0]const u8) void {
    const text_size = rl.measureTextEx(
        font,
        text,
        font_size_px,
        font_spacing_px,
    );

    const text_position = rl.Vector2{
        .x = (screen_width - text_size.x) / 2,
        .y = (screen_height - text_size.y) / 2,
    };

    rl.drawTextEx(
        font,
        text,
        text_position,
        font_size_px,
        font_spacing_px,
        color,
    );
}

fn draw_board() void {
    const cell_width_px: f32 = @floatFromInt(screen_width / board_size);
    const cell_height_px: f32 = @floatFromInt(screen_height / board_size);

    for (game.board, 0..) |row, row_index| {
        for (row, 0..) |cell, column_index| {
            // If cell is not taken, nothing to set
            const mark = cell orelse continue;
            const text = text_from_mark(mark);

            const row_index_f32: f32 = @floatFromInt(row_index);
            const column_index_f32: f32 = @floatFromInt(column_index);
            const text_font_size = cell_width_px / 2;

            const text_size = rl.measureTextEx(
                font,
                text,
                text_font_size,
                0,
            );

            assert(text_size.x <= cell_width_px);
            assert(text_size.y <= cell_height_px);

            const text_position = rl.Vector2{
                .x = cell_width_px * column_index_f32 + (cell_width_px - text_size.x) / 2,
                .y = cell_height_px * row_index_f32 + (cell_height_px - text_size.y) / 2,
            };

            rl.drawTextEx(font, text, text_position, cell_width_px / 2, font_spacing_px, color);
        }
    }
}

fn draw_grid() void {
    const border_offset_px = grid_border_thickness_px / 2;
    const cell_width_px: i32 = @intCast(screen_width / board_size);
    const cell_height_px: i32 = @intCast(screen_height / board_size);

    for (1..board_size) |line_index| {
        const line_index_i32: i32 = @intCast(line_index);

        const vertical_border_x = cell_width_px * line_index_i32 - border_offset_px;
        rl.drawRectangle(vertical_border_x, 0, grid_border_thickness_px, @intCast(screen_height), color);

        const horizontal_border_y = cell_height_px * line_index_i32 - border_offset_px;
        rl.drawRectangle(0, horizontal_border_y, @intCast(screen_width), grid_border_thickness_px, color);
    }
}

fn update_game() void {
    switch (active_screen) {
        .welcome => {
            if (rl.isKeyPressed(.enter) or rl.isMouseButtonPressed(.left)) {
                init_game();
                active_screen = .game;
            }
        },
        .game => {
            if (rl.isMouseButtonPressed(.left)) {
                const mouse_position = rl.getMousePosition();

                const x: u8 = @intFromFloat(@divExact(mouse_position.y, cell_size));
                const y: u8 = @intFromFloat(@divExact(mouse_position.x, cell_size));

                take_position(x, y) catch |err| switch (err) {
                    error.PositionOccupied => {},
                };
            }
        },
        .ending => {
            if (rl.isKeyPressed(.r) or rl.isMouseButtonPressed(.left)) {
                init_game();
                active_screen = .game;
            }
        },
    }
}

fn draw_game() void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(.black);

    switch (active_screen) {
        .welcome => {
            draw_centered_text("Welcome! Press enter to start");
        },
        .game => {
            draw_grid();
            draw_board();
        },
        .ending => {
            switch (game.status) {
                .o_won => draw_centered_text("O won!"),
                .x_won => draw_centered_text("X won!"),
                .tie => draw_centered_text("It's a tie!"),
                .started => {},
            }
        },
    }

    rl.enableEventWaiting();
}

fn update_draw_frame() void {
    update_game();
    draw_game();
}

pub fn main() !void {
    try init_window();
    defer deinit_window();

    while (!rl.windowShouldClose()) {
        update_draw_frame();
    }
}
