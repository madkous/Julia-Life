module Life

# SDL init
using SimpleDirectMediaLayer
const SDL = SimpleDirectMediaLayer

# "#000000",  /*  0: black    */    "#454444",  /*  8: brblack  */
# "#ce281f",  /*  1: red      */    "#ee534b",  /*  9: brred    */
# "#00853e",  /*  2: green    */    "#2f8557",  /* 10: brgreen  */
# "#e8bf04",  /*  3: yellow   */    "#ffde47",  /* 11: bryellow */
# "#009ddc",  /*  4: blue     */    "#5cb7dc",  /* 12: brblue   */
# "#98005d",  /*  5: magenta  */    "#983f75",  /* 13: brmagenta*/
# "#2cba96",  /*  6: cyan     */    "#97cec0",  /* 14: brcyan   */
# "#c3c2c2",  /*  7: white    */    "#e3e3e3",  /* 15: brwhite  */

## Torus structure definitons
mutable struct Torus{T,N} <: AbstractArray{T,N}
	grid::Array{T,N}
end

Base.size(A::Torus{T,N}) where {T,N} = size(A.grid)
function Base.getindex(A::Torus{T,N}, I::Vararg{Int,N}) where {T,N}
	I = I .% size(A)
	I = map((a,b,c) -> c ? a + b : a, I, size(A), I .< 0)
	Base.getindex(A.grid, (I .+ 1)...)
end
function Base.setindex!(A::Torus{T,N}, v, I::Vararg{Int,N}) where {T,N}
	I = I .% size(A)
	I = map((a,b,c) -> c ? a + b : a, I, size(A), I .< 0)
	Base.setindex!(A.grid, v, (I .+ 1)...)
end

## World structure definitions
mutable struct World
	grid::Torus{Int,2}
	aux::Torus{Int,2}
	cursor::Tuple{Int64,Int64}
	dim::Int
	active::Bool

	function World(N::Int)
		grid = Torus(zeros(Int, N, N))
		aux  = Torus(zeros(Int, N, N))
		cursor = (N÷2, N÷2)
		dim = N
		active = false
		new(grid, aux, cursor, dim, active)
	end
end

function mv_cur_f(wld::World, n::Int)
	(x,y) = wld.cursor
	y = (y - n) % wld.dim
	(y < 0) && (y += wld.dim)
	wld.cursor = (x,y)
end

function mv_cur_b(wld::World, n::Int)
	(x,y) = wld.cursor
	y = (y + n) % wld.dim
	wld.cursor = (x,y)
end

function mv_cur_l(wld::World, n::Int)
	(x,y) = wld.cursor
	x = (x - n) % wld.dim
	(x < 0) && (y += wld.dim)
	wld.cursor = (x,y)
end

function mv_cur_r(wld::World, n::Int)
	(x,y) = wld.cursor
	x = (x + n) % wld.dim
	wld.cursor = (x,y)
end

## Conway's Life
##   life-wxyz
##   n live neighbors
##   live if w ≤ n ≤ x
##   grow if y ≤ n ≤ z
RULES = (2, 3, 3, 3)
N = 50 # grid size
# pattern library
block = [1 1;
	 1 1]
glider = [0 1 0;
	  0 0 1;
	  1 1 1]
blinker = [1 1 1]
toad = [0 1 1 1;
	1 1 1 0]
beacon = [1 1 0 0;
	  1 0 0 0;
	  0 0 0 1;
	  0 0 1 1]
lwss = [1 0 0 1 0;
	0 0 0 0 1;
	1 0 0 0 1;
	0 1 1 1 1]

function count_neighbors(wld::World, I::Vararg{Int,2})
	cnt = 0
	N = 2
	for a in eachindex(view(ones(ntuple(i->3,N)), ntuple(i->1:3,N)...))
		cnt += wld.grid[(I .+ Tuple(a) .- 2)...]
	end
	return cnt - wld.grid[I...]
end

# constants
bg_col = (0, 0, 0, 255)
bord_col = (Int(0x45), Int(0x44), Int(0x44), 255)
dead_col = (Int(0xe3), Int(0xe3), Int(0xe3))
live_col = (Int(0xce), Int(0x28), Int(0x1f))
curs_col = (Int(0xe8), Int(0xbf), Int(0x04), 255)
cell_width = 10
grid_width = 1
#= max_it = 1_000_000 # UNUSED =#
upd_freq = 100
drw_freq = 10
sleep_int = 0.005
win_heigth = 600
win_width = 800
main_view_heigth = 50
main_view_width = 50

# encapsulates game rules
function create_stepper(N::Int, W::Int, X::Int, Y::Int, Z::Int)
	function (wld::World)
		for u in 1:N, v in 1:N
			wld.aux[u,v] = count_neighbors(wld, u, v)
		end
		for u in 1:N, v in 1:N
			!(W ≤ wld.aux[u,v] ≤ X) && (wld.grid[u,v] = 0)
			(Y ≤ wld.aux[u,v] ≤ Z) && (wld.grid[u,v] = 1)
		end
	end
end

function place_object(wld::World, coords::Tuple, obj::Array)
	wld.grid[map((a,b) -> a:(a+b-1), coords, size(obj))...] = obj
end

function flip_cell(wld::World, coords::Tuple)
	wld.grid[coords...] = (wld.grid[coords...] + 1) % 2
end

function populate_world(wld::World)
	place_object(wld, (20,1), lwss)
	place_object(wld, (1,1), beacon)
	place_object(wld, (15,15), toad)
end

# TODO fix cursor math
function get_cell(coords...)
	(coords .- 5) .÷ (cell_width + grid_width) .+ 1
end

## Graphics
function init_SDL()
	SDL.Init(UInt32(SDL.INIT_VIDEO | SDL.INIT_TIMER))
	#= SDL.TTF_Init() =#
	win = SDL.CreateWindow("It's A Life!",
			      Int32(100), Int32(100),
			      Int32(win_width), # N*(cell_width + grid_width)+10),
			      Int32(win_heigth), # N*(cell_width + grid_width)+10),
			      UInt32(SDL.WINDOW_SHOWN))
	ren = SDL.CreateRenderer(win, Int32(-1),
				 UInt32(SDL.RENDERER_ACCELERATED
					| SDL.RENDERER_PRESENTVSYNC))
	#= font = TTF_OpenFont("/usr/share/fonts/inconsolata-lgc/inconsolatalgc.ttf", 14) =#
	return win, ren
end

function quit_SDL()
	#= SDL.Mix_CloseAudio() =#
	#= SDL.TTF_Quit() =#
	SDL.Quit()
end

function upd_scrn(wld::World, win::Ptr{SDL.Window}, ren::Ptr{SDL.Renderer})
	viewport = SDL.Rect(0, 0, win_width, win_heigth)
	SDL.RenderSetViewport(ren, pointer_from_objref(viewport))
	SDL.SetRenderDrawColor(ren, bg_col...)
	SDL.RenderClear(ren)
	SDL.SetRenderDrawColor(ren, bord_col...)
	SDL.RenderDrawRect(ren, pointer_from_objref(SDL.Rect(0,0,win_width,win_heigth)))

	draw_world(wld, win, ren)
	draw_minimap(wld, win, ren)
	#= draw_gamestatus(wld, win, ren) =#

	SDL.RenderPresent(ren)
end

function draw_minimap(wld::World, win::Ptr{SDL.Window}, ren::Ptr{SDL.Renderer})
	N = wld.dim
	n = 200 ÷ N
	viewport = SDL.Rect(10 + main_view_width*(cell_width+grid_width) - grid_width,
			    5, 200, 200)
	SDL.RenderSetViewport(ren, pointer_from_objref(viewport))
	SDL.SetRenderDrawColor(ren, dead_col..., 255)
	#= rect = SDL.Rect(0, 0, 200, 200) =#
	#= SDL.RenderDrawRect(ren, pointer_from_objref(rect)) =#
	#= SDL.RenderFillRect(ren, pointer_from_objref(rect)) =#
		for u in 0:N-1, v in 0:N-1
			if wld.grid[u,v] == 1
				rect = SDL.Rect(n * u, n * v, n, n)
				SDL.RenderFillRect(ren, pointer_from_objref(rect))
				SDL.RenderDrawRect(ren, pointer_from_objref(rect))
			end
		end
	#= rect = SDL.Rect(0, 0, 200, 200) =#
	#= SDL.RenderFillRect(ren, pointer_from_objref(rect)) =#
	#= SDL.RenderDrawRect(ren, pointer_from_objref(rect)) =#
end

function draw_world(wld::World, win::Ptr{SDL.Window}, ren::Ptr{SDL.Renderer})
	viewport = SDL.Rect(5, 5, main_view_width*(cell_width+grid_width) - grid_width,
			    main_view_heigth*(cell_width+grid_width) - grid_width)
	SDL.RenderSetViewport(ren, pointer_from_objref(viewport))
	x, y = wld.cursor
	x_width, y_width = main_view_width ÷ 2, main_view_heigth ÷ 2
	for u in (x - x_width):(x + x_width),
		v in (y - y_width):(y + y_width)
		if (u,v) == wld.cursor
			SDL.SetRenderDrawColor(ren, curs_col...)
		elseif wld.grid[u,v] == 1
			SDL.SetRenderDrawColor(ren, live_col..., 255)
		else
			SDL.SetRenderDrawColor(ren, dead_col..., 255)
		end
		rect = SDL.Rect((u - x + x_width)*(cell_width + grid_width),
				(v - y + y_width)*(cell_width + grid_width),
				cell_width, cell_width)
		SDL.RenderFillRect(ren, pointer_from_objref(rect))
	end
end

#= function draw_gamestatus(wld::World, win::Ptr{SDL.Window}, ren::Ptr{SDL.Renderer}) =#

function main()
	try
		win, ren = init_SDL()
		world = World(N)
		populate_world(world)
		println("Running life-$(RULES...)")
		step_world = create_stepper(N, RULES...)
		playing = true
		time = SDL.GetTicks()

		while playing
			new_time = SDL.GetTicks()
			if world.active && (new_time - time >= upd_freq)
				step_world(world)
				time = new_time
			end

			if new_time - time >= drw_freq
				upd_scrn(world, win, ren)
			end

			while !((e = SDL.event()) isa Nothing)
				t = e._type
				if t == SDL.MOUSEBUTTONDOWN
					flip_cell(world, get_cell(SDL.mouse_position()...))
				elseif t == SDL.KEYDOWN
					if e.keysym.sym == SDL.SDLK_q
						playing = false
					elseif e.keysym.sym == SDL.SDLK_p
						world.active = !world.active
					elseif e.keysym.sym == SDL.SDLK_SPACE
						flip_cell(world, world.cursor)
					elseif e.keysym.sym == SDL.SDLK_UP ||
						e.keysym.sym == SDL.SDLK_k
						mv_cur_f(world, 1)
					elseif e.keysym.sym == SDL.SDLK_DOWN ||
						e.keysym.sym == SDL.SDLK_j
						mv_cur_b(world, 1)
					elseif e.keysym.sym == SDL.SDLK_LEFT ||
						e.keysym.sym == SDL.SDLK_h
						mv_cur_l(world, 1)
					elseif e.keysym.sym == SDL.SDLK_RIGHT ||
						e.keysym.sym == SDL.SDLK_l
						mv_cur_r(world, 1)
					end
				end
			end
			sleep(sleep_int)
		end
	finally
		quit_SDL()
	end
end

end # module
