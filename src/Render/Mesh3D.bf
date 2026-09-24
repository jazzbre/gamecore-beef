using NoGraphicsAPI;
using System;
using System.Collections;

namespace GameCore
{
    [CRepr]
    struct Mesh3DVertex
    {
        public Vector3 position;
        public Vector3 normal;
        public Vector4 uv;
        public uint32 color;

        public this(Vector3 _position, Vector3 _normal, Vector4 _uv, uint32 _color)
        {
            position = _position;
            normal = _normal;
            uv = _uv;
            color = _color;
        }

        public static Mesh3DVertex Lerp(Mesh3DVertex a, Mesh3DVertex b, float delta)
        {
            return .(.Lerp(a.position, b.position, delta), .Lerp(a.normal, b.normal, delta), .Lerp(a.uv, b.uv, delta), a.color);
        }
    }

    class Mesh3D
    {
        public GpuBuffer VertexBufferHandle { get; private set; }
        public GpuBuffer IndexBufferHandle { get; private set; }

        public List<Mesh3DVertex> Vertices { get; private set; }
        public List<uint16> Indices { get; private set; }

        public Vector3 MinBounds { get; private set; }
        public Vector3 MaxBounds { get; private set; }

        public Vector4 MinUV { get; private set; }
        public Vector4 MaxUV { get; private set; }

        public static VertexLayout vertexLayout;

        public this()
        {
            VertexBufferHandle = .Null;
            IndexBufferHandle = .Null;
        }

        public ~this()
        {
            Destroy();
            delete Vertices;
            delete Indices;
        }

        public void Initialize(int vertexCount, int indexCount)
        {
            Destroy();
            if (vertexLayout.hash == 0)
            {
                vertexLayout.Begin();
                vertexLayout.Add(VertexAttribute.Position, 3, VertexComponent.Float, false, false);
                vertexLayout.Add(VertexAttribute.Normal, 3, VertexComponent.Float, false, false);
                vertexLayout.Add(VertexAttribute.TexCoord0, 4, VertexComponent.Float, false, false);
                vertexLayout.Add(VertexAttribute.Color0, 4, VertexComponent.Uint8, true, false);
                vertexLayout.End();
            }
            if (Vertices == null)
            {
                Vertices = new List<Mesh3DVertex>();
            }
            if (Indices == null)
            {
                Indices = new List<uint16>();
            }
            Vertices.Count = vertexCount;
            Indices.Count = indexCount;
        }

        public void Initialize(int vertexCount)
        {
            Initialize(vertexCount, (vertexCount - 2) * 3);
            int index = 0;
            for (int i = 0; i < Vertices.Count - 2; ++i)
            {
                var vertexIndex = (uint16)i;
                Indices[index++] = 0;
                Indices[index++] = vertexIndex + 1;
                Indices[index++] = vertexIndex + 2;
            }
        }

        public void Create()
        {
            VertexBufferHandle = GpuBuffer.CreateVertices(&Vertices[0], (uint32)(Vertices.Count * sizeof(Mesh3DVertex)), vertexLayout);
            IndexBufferHandle = GpuBuffer.CreateIndices(&Indices[0], (uint32)(Indices.Count * sizeof(uint16)));
            MinBounds = MinBounds = Vertices[0].position;
            MinUV = MaxUV = Vertices[0].uv;
            for (var vertex in Vertices)
            {
                MinBounds = .Min(MinBounds, vertex.position);
                MaxBounds = .Max(MaxBounds, vertex.position);
                MinUV = .Min(MinUV, vertex.uv);
                MaxUV = .Max(MaxUV, vertex.uv);
            }
        }

        public void Destroy()
        {
            if (VertexBufferHandle.Valid)
            {
                VertexBufferHandle.Dispose();
                VertexBufferHandle = .Null;
            }
            if (IndexBufferHandle.Valid)
            {
                IndexBufferHandle.Dispose();
                IndexBufferHandle = .Null;
            }
        }

        public void Render(RenderCommandBuffer commandBuffer, Matrix4 worldMatrix, Shader shader, GpuTexture[] textureHandles, Color color = Color.White, RenderState? state = null, SamplerDesc? sampler = null, int programIndex = 0, Camera camera = null)
        {
            if (!VertexBufferHandle.Valid || !IndexBufferHandle.Valid)
                return;
            var renderState = state.GetValueOrDefault(RenderState.DepthTested);
            if (camera != null)
                renderState.Depth.depth_compare = camera.DepthTest;
            RenderManager.Draw(commandBuffer, shader, programIndex, VertexBufferHandle, IndexBufferHandle, (.)Vertices.Count, (.)Indices.Count,
                worldMatrix, .(color.r, color.g, color.b, color.a), .Zero, textureHandles, renderState, sampler);
        }
    }
}
