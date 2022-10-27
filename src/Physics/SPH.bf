using System;
using System.Collections;

namespace Dedkeni
{
	class SPH
	{
		public const float Scale = 0.5f;
		public const float Gravity = 500.0f;// * Scale;
		public const float InteractionRadius = 40.0f * Scale;
		public const float LinearViscocity = 0.001f;
		public const float QuadraticViscocity = 0.01f;
		public const float RestDensity = 100.0f * Scale;
		public const float Stiffness = 15.0f * Scale;
		public const float StiffnessNear = 600.0f * Scale;

		public const int32 GridCellSize = (.)(20 * Scale);
		public const int32 GridHalfColumns = 1000 / GridCellSize / 2;
		public const int32 GridHalfRows = 500 / GridCellSize / 2;
		public const float CollisionRadius = 20.0f * Scale;

		public typealias CollisionCallback = delegate bool(ref Vector2 previousPosition, ref Vector2 position, ref Vector2 velocity, float radius);

		SpatialHashGrid grid = null ~ delete _;
		List<Particle> particles = new .() ~ DeleteContainerAndItems!(_);
		uint32 particleIndex = 0;

		public CollisionCallback collisionCallback = null;

		public int ParticleCount
		{
			get { return particles.Count; }
		}

		public List<Particle> Particles => particles;

		public this()
		{
			grid = new SpatialHashGrid(GridCellSize, GridHalfColumns, GridHalfRows);
		}

		public void AddParticle(Vector2 position, Vector2 velocity = .Zero, Color color = .White)
		{
			var particle = new Particle(position, 1.0f / InteractionRadius, particleIndex++);
			particle.velocity = velocity;
			particles.Add(particle);
		}

		public void Update(float deltaTime)
		{
			if (ParticleCount == 0)
			{
				return;
			}
			ApplyExternalForces(deltaTime);
			ApplyViscosity(deltaTime);
			AdvanceParticles(deltaTime);
			grid.UpdateNeighbours(particles);
			DoubleDensityRelaxation(deltaTime);
			ResolveCollisions(deltaTime);
			UpdateVelocity(deltaTime);
			ColorParticles();
		}

		void ApplyExternalForces(float dt)
		{
			for (var p in particles)
			{
				p.velocity.y -= Gravity * dt;
			}
		}

		void ApplyViscosity(float dt)
		{
			for (var p in particles)
			{
				for (var n in p.neighbours)
				{
					if (p.index < n.index)
					{
						let v = n.position - p.position;
						let vLength = v.Length;
						let vn = v / vLength;
						let u = Vector2.Dot(p.velocity - n.velocity, vn);
						if (u > 0.0f)
						{
							let q = 1.0f - vLength * p.ooRadius;
							var impulse = 0.5f * dt * q * (LinearViscocity * u + QuadraticViscocity * u * u) * vn;
							if (Math.Abs(impulse.x) > 10000.0f) impulse.x /= 10000.0f;
							if (Math.Abs(impulse.y) > 10000.0f) impulse.y /= 10000.0f;
							p.velocity -= impulse;
							n.velocity += impulse;
						}
					}
				}
			}
		}

		void AdvanceParticles(float deltaTime)
		{
			// Update position with its accumulated forces
			// with a prediction-relaxation integrator
			for (var i = 0; i < particles.Count; ++i)
			{
				var p = particles[i];
				p.previousPosition = p.position;
				p.position += p.velocity * deltaTime;

				// Remove particles outside of grid
				if (p.position.x < -grid.HalfWidth || p.position.x > grid.HalfWidth ||
					p.position.y < -grid.HalfHeight || p.position.y > grid.HalfHeight)
				{
					delete p;
					particles.RemoveAt(i--);
					continue;
				}
			}
		}

		void DoubleDensityRelaxation(float deltaTime)
		{
			for (var p in particles)
			{
				// Sample neighbours for particle density
				// with a quadratic spike kernel
				p.density = p.densityNear = 0.0f;
				for (var n in p.neighbours)
				{
					let v = n.position - p.position;
					let q = 1.0f - v.Length * p.ooRadius;
					p.density += q * q;
					p.densityNear += q * q * q;
				}

				// The higher rest density is, the higher the density and surface tension
				p.pressure = Stiffness * (p.density - p.restDensity);
				p.pressureNear = StiffnessNear * p.densityNear;

				// Keep within sensible range to avoid infinity/NaN (particles disappearing)
				if (p.pressure + p.pressureNear < 0.000001f || p.pressure + p.pressureNear > 1000000f)
				{
					p.pressure = 0;
					p.pressureNear = 0;
				}

				var dx = Vector2.Zero;
				for (var n in p.neighbours)
				{
					let v = n.position - p.position;
					let squaredLength = v.LengthSquared;
					if (squaredLength > 0)
					{
						let length = Math.Sqrt(squaredLength);
						let q = 1.0f - length * p.ooRadius;
						let displacement = 0.5f * deltaTime * deltaTime * (p.pressure * q + p.pressureNear * q * q) * v / length;
						n.position += displacement;
						dx -= displacement;
					}
				}
				p.position += dx;
			}
		}

		void ResolveCollisions(float deltaTime)
		{
			if (collisionCallback == null)
			{
				return;
			}
			for (var p in particles)
			{
				collisionCallback(ref p.previousPosition, ref p.position, ref p.velocity, CollisionRadius);
			}
		}

		void UpdateVelocity(float deltaTime)
		{
			let ooDeltaTime = 1.0f / deltaTime;
			for (var p in particles)
			{
				p.velocity = (p.position - p.previousPosition) * ooDeltaTime;
			}
		}

		void ColorParticles()
		{
			for (var p in particles)
			{
				p.color.a = 1 - 1 / p.density;
			}
		}

		public class Particle
		{
			public Vector2 position;
			public Vector2 previousPosition;
			public Vector2 velocity;
			public Color color;
			public float restDensity;
			public float density;
			public float densityNear;
			public float pressure;
			public float pressureNear;
			public float ooRadius;
			public PointInt32 key;
			public List<Particle> neighbours = new .() ~ delete _;
			public uint32 index = 0;

			public this(Vector2 _position, float _ooRadius, uint32 _index)
			{
				position = previousPosition = _position;
				color = Color(1.0f, 1.0f, 1.0f, 1.0f);
				restDensity = RestDensity;
				ooRadius = _ooRadius;
				index = _index;
			}

			public this(Vector2 _position, Color _color, float _ooRadius, uint32 _index)
			{
				position = previousPosition = _position;
				color = _color;
				restDensity = RestDensity;
				ooRadius = _ooRadius;
				index = _index;
			}

			public this(Vector2 _position, float restdensity, Color _color, float _ooRadius, uint32 _index)
			{
				position = previousPosition = _position;
				color = _color;
				restDensity = restdensity;
				ooRadius = _ooRadius;
				index = _index;
			}
		}

		class SpatialHashGrid
		{
			int32 cellSize, rows, columns, halfRows, halfColumns;
			Dictionary<int, List<Particle>> buckets = new .() ~ delete _;
			List<List<Particle>> freeLists = new .() ~ delete _;
			List<List<Particle>> allLists = new .() ~ DeleteContainerAndItems!(_);

			public int HalfWidth
			{
				get { return cellSize * halfColumns; }
			}

			public int HalfHeight
			{
				get { return cellSize * halfRows; }
			}

			public this(int32 cellsize, int32 halfColumns, int32 halfRows)
			{
				this.cellSize = cellsize;
				this.halfColumns = halfColumns;
				this.halfRows = halfRows;
				this.columns = halfColumns * 2 + 1;
				this.rows = halfRows * 2 + 1;
			}

			public void UpdateNeighbours(List<Particle> particles)
			{
				// Clear buckets (recycle lists)
				for (var pair in buckets)
				{
					pair.value.Clear();
					freeLists.Add(pair.value);
				}
				buckets.Clear();
				for (var i = 0; i < particles.Count; ++i)
				{
					var p = particles[i];
					// Remove particles outside of grid
					if (p.position.x < -HalfWidth || p.position.x > HalfWidth ||
						p.position.y < -HalfHeight || p.position.y > HalfHeight)
					{
						delete p;
						particles.RemoveAt(i--);
						continue;
					}

					// Make key from particle's position
					p.key = GetHashKey(p.position);

					// Add particle to the cell and neighbour's cell
					for (var x = p.key.x - 1; x <= p.key.x + 1; x++)
					{
						for (var y = p.key.y - 1; y <= p.key.y + 1; y++)
						{
							var hashValue = GetHashValue(x, y);

							List<Particle> list;
							if (buckets.TryGetValue(hashValue, out list))
							{
								list.Add(p);
							}
							else
							{
								if (freeLists.Count > 0)
								{
									list = freeLists.PopBack();
								} else
								{
									list = new .();
									allLists.Add(list);
								}
								buckets.Add(hashValue, list);
								buckets[hashValue].Add(p);
							}
						}
					}
				}

				for (var p in particles)
				{
					p.neighbours.Clear();
					for (var n in buckets[GetHashValue(p.key.x, p.key.y)])
					{
						if (p != n)
						{
							if ((p.position - n.position).LengthSquared < GridCellSize * GridCellSize)
							{
								p.neighbours.Add(n);
							}
						}
					}
				}
			}

			int32 GetHashValue(int32 x, int32 y)
			{
				return x + y * rows;
			}

			PointInt32 GetHashKey(Vector2 position)
			{
				var x = (int32)Math.Floor(position.x / cellSize);
				var y = (int32)Math.Floor(position.y / cellSize);
				return .(x, y);
			}

		}
	}
}
