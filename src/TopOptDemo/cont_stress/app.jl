using TopOpt, LinearAlgebra, StatsFuns
using TopOptMakie
using VTKDataIO
using PyCall
using VTKDataTypes
using DashVtk
using Dash
using DashHtmlComponents

#dash = pyimport("dash")
#dash_html = pyimport("dash_html_components")
dash_vtk = pyimport("dash_vtk")

E = 1.0 # Young’s modulus
v = 0.3 # Poisson’s ratio
f = 1.0 # downward force
rmin = 4.0 # filter radius
xmin = 0.0001 # minimum density
problem_size = (160, 40)
x0 = fill(1.0, prod(problem_size)) # initial design
p = 4.0 # penalty
stress_threshold = 1.0 # maximum von Mises stress
compliance_threshold = 800 # maximum compliance

problem = PointLoadCantilever(Val{:Linear}, problem_size, (1.0, 1.0), E, v, f)
#problem = HalfMBB(Val{:Linear}, problem_size, (1.0, 1.0), E, v, f)

solver = FEASolver(Displacement, Direct, problem, xmin = xmin)

cheqfilter = DensityFilter(solver, rmin = rmin)
stress = TopOpt.MicroVonMisesStress(solver)
comp = TopOpt.Compliance(problem, solver)

function obj(x)
    # minimize volume
    return sum(cheqfilter(x)) / length(x)
end
function constr1(x)
    # L-20 norm aggregation to approximate maximum function
    return norm(stress(cheqfilter(x)), 20) - stress_threshold
end
function constr2(x)
    # compliance upper-bound
    return comp(cheqfilter(x)) - compliance_threshold
end

m = Model(obj)
addvar!(m, zeros(length(x0)), ones(length(x0)))
Nonconvex.add_ineq_constraint!(m, constr1)
Nonconvex.add_ineq_constraint!(m, constr2)

options = MMAOptions(
    maxiter=1000, tol = Tolerance(kkt = 1e-4, f = 1e-4),
)
TopOpt.setpenalty!(solver, p)
@time r = Nonconvex.optimize(
    m, MMA87(dualoptimizer = ConjugateGradient()),
    x0, options = options,
);

@show obj(r.minimizer)
@show constr1(r.minimizer)
@show constr2(r.minimizer)
@show maximum(stress(cheqfilter(r.minimizer)))
topology = cheqfilter(r.minimizer);

mesh = VTKUnstructuredData(problem)
topology = round.(topology)
inds = findall(isequal(0), topology)
deleteat!(mesh.cell_connectivity, inds)
deleteat!(mesh.cell_types, inds)

pymesh = PyVTK(mesh)
dash_vtk_utils = pyimport("dash_vtk.utils")
dash_vtk_utils.to_mesh_state
state = dash_vtk_utils.to_mesh_state(pymesh)

content = vtk_view([
        vtk_geometryrepresentation([
        vtk_mesh(state=state)
    ]),
])

app = dash()

app.layout = html_div() do 
    html_div(
    style = Dict(
        "width" => "100%", 
        "height" => "400px"
    ),
    children=[content],
    )
end

run_server(app, "0.0.0.0", debug = true)